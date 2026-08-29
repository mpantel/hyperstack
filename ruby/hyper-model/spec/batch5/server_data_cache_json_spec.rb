require 'spec_helper'
require 'test_components'

# The tree ServerDataCache serializes has to be keyed consistently: every key in
# it crosses the wire as a JSON string, so a Symbol key and a String key that
# spell the same thing collapse into one -- a duplicate key in the generated
# JSON. `merge(id: id)` used to add a record's id under a Symbol while every
# other key (jsonize'd method names, the inheritance column) was a String, so any
# node whose record had also had its `id` attribute fetched carried both "id" and
# :id. activesupport warns about that today and json 3.0 raises. (#82)
#
# The node in question is the one built for a record reached by a *named* method
# -- an association -- which is why the vectors below walk TodoItem -> user
# rather than just fetching attributes off a record found directly.
describe "ReactiveRecord::ServerDataCache serialized tree" do

  before(:each) do
    ActiveRecord::Base.public_columns_hash
  end

  let!(:user) do
    User.create(first_name: 'Mitch', last_name: 'VanDuyn', email: 'mitch@catprint.com')
  end

  let!(:todo) do
    TodoItem.create(title: 'a todo for mitch', description: 'a description', user: user)
  end

  # the vector the client builds for `TodoItem.find_by(id: n)`
  let(:find_todo) do
    ['TodoItem', 'all', ['___hyperstack_internal_scoped_find_by', { 'id' => todo.id }], '*0']
  end

  # fetching the id attribute alongside another attribute is what puts an "id"
  # key in the node before the merge adds one of its own.
  let(:tree) do
    ReactiveRecord::ServerDataCache[
      [], [],
      [
        find_todo + ['title'],
        find_todo + ['user', 'id'],
        find_todo + ['user', 'first_name']
      ],
      user # acting_user: User only permits viewing itself, TodoItem its owner's
    ]
  end

  # walks every Hash in the tree, yielding it, so the assertions can be made on
  # the whole structure rather than on the one node we happen to name below.
  def each_node(tree, &block)
    return unless tree.is_a?(Hash)
    block.call(tree)
    tree.each_value { |value| each_node(value, &block) }
  end

  # the User node hanging off the TodoItem, i.e. the one as_hash merges the id into
  def user_node
    finder = ['___hyperstack_internal_scoped_find_by', { 'id' => todo.id }].to_json
    tree['TodoItem']['all'][finder][todo.id]['user']
  end

  it "keys the whole tree with Strings and Integers only" do
    bad_keys = []
    each_node(tree) do |node|
      bad_keys += node.keys.reject { |key| key.is_a?(String) || key.is_a?(Integer) }
    end
    expect(bad_keys).to eq []
  end

  it "never puts two spellings of the same key in one node" do
    duplicated = []
    each_node(tree) do |node|
      duplicated += node.keys.group_by(&:to_s).select { |_, keys| keys.length > 1 }.keys
    end
    expect(duplicated).to eq []
  end

  it "puts an associated record's id under the String key 'id'" do
    expect(user_node['id']).to eq [user.id]
    expect(user_node['first_name']).to eq ['Mitch']
    expect(user_node.keys).not_to include :id
  end

  it "survives a JSON round trip without losing or duplicating the id" do
    encoded = user_node.to_json
    expect(encoded.scan('"id"').length).to eq 1
    expect(JSON.parse(encoded)['id']).to eq [user.id]
  end

  # json warns on a duplicate key today and raises from 3.0; either way nothing
  # about encoding this tree should complain.
  it "encodes without a duplicate key warning" do
    captured = StringIO.new
    original = $stderr
    begin
      $stderr = captured
      tree.to_json
    ensure
      $stderr = original
    end
    expect(captured.string).not_to include 'duplicate key'
  end
end
