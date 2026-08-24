require 'spec_helper'
require 'test_components'

# A save or destroy of an *existing* record arrives with the record's primary
# key, which the server used to resolve with a bare `Model.find(id)`.  That made
# `update_permitted?`/`destroy_permitted?` the only gate, so a client whose
# policy merely asks "is someone signed in" could name the id of any record of
# that model - including ones the read regulations would never have shown it.
describe 'write path record resolution' do
  before(:each) do
    stub_const 'TestUser', Class.new
    TestUser.class_eval do
      include ActiveModel::Model
      # acting_user always responds to `id` in a real app - the connection
      # machinery keys channels off it (InternalPolicy.channel_to_string).
      attr_accessor :id, :name
    end

    stub_const 'TestApplicationPolicy', Class.new
    TestApplicationPolicy.class_eval do
      regulate_class_connection { self }
      regulate_instance_connections(TestModel) { TestModel.find_by_test_attribute(name) }
      regulate_broadcast(TestModel) { |policy| policy.send_all.to(self) }
    end

    # other specs in this batch permanently redefine ActiveRecord::Base#view_permitted?
    # to return true, so pin the real implementation onto TestModel for the
    # duration of the example (and take it off again below).
    TestModel.class_eval do
      def view_permitted?(attribute)
        Hyperstack::InternalPolicy
          .accessible_attributes_for(self, acting_user)
          .include? attribute.to_sym
      end
    end

    # we are testing record *resolution*, so let the CRUD regulations say yes to
    # everything, exactly as a "is someone signed in" policy would.
    allow_any_instance_of(TestModel).to receive(:create_permitted?).and_return(true)
    allow_any_instance_of(TestModel).to receive(:update_permitted?).and_return(true)
    allow_any_instance_of(TestModel).to receive(:destroy_permitted?).and_return(true)
  end

  after(:each) do
    TestModel.send(:remove_method, :view_permitted?) if TestModel.instance_methods(false).include?(:view_permitted?)
  end

  let(:acting_user) { TestUser.new(id: 1, name: 'mine') }
  let!(:mine)     { TestModel.create!(test_attribute: 'mine',     completed: false) }
  let!(:not_mine) { TestModel.create!(test_attribute: 'not-mine', completed: false) }

  def save(record, attributes)
    ReactiveRecord::Base.save_records(
      [{
        id: 1,
        model: 'TestModel',
        vector: ['TestModel'],
        attributes: { 'id' => record.id }.merge(attributes)
      }],
      [], acting_user, false, true
    )
  end

  def destroy(record)
    ReactiveRecord::Base.destroy_record('TestModel', record.id, ['TestModel'], acting_user)
  end

  it 'saves a record the acting user is permitted to see' do
    expect(save(mine, 'completed' => true)[:success]).to be_truthy
    expect(mine.reload.completed).to be_truthy
  end

  it 'will not save a record the acting user cannot see' do
    result = save(not_mine, 'completed' => true)
    expect(result[:success]).to be_falsy
    expect(result[:message]).to be_a Hyperstack::AccessViolation
    expect(not_mine.reload.completed).to be_falsy
  end

  it 'destroys a record the acting user is permitted to see' do
    expect(destroy(mine)[:success]).to be_truthy
    expect(TestModel.find_by(id: mine.id)).to be_nil
  end

  it 'will not destroy a record the acting user cannot see' do
    result = destroy(not_mine)
    expect(result[:success]).to be_falsy
    expect(result[:message]).to be_a Hyperstack::AccessViolation
    expect(not_mine.reload).to be_present
  end

  it 'still creates new records, which have no id to resolve' do
    result = ReactiveRecord::Base.save_records(
      [{
        id: 1,
        model: 'TestModel',
        vector: ['TestModel', ['new', 1]],
        attributes: { 'test_attribute' => 'brand new' }
      }],
      [], acting_user, false, true
    )
    expect(result[:success]).to be_truthy
    expect(TestModel.find_by(test_attribute: 'brand new')).to be_present
  end

  context 'with verify_record_visibility_on_write turned off' do
    around(:each) do |example|
      Hyperstack.verify_record_visibility_on_write = false
      begin
        example.run
      ensure
        Hyperstack.verify_record_visibility_on_write = true
      end
    end

    it 'reverts to resolving the id with an unscoped find' do
      expect(save(not_mine, 'completed' => true)[:success]).to be_truthy
      expect(not_mine.reload.completed).to be_truthy
    end
  end
end
