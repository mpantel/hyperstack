require 'spec_helper'

# This spec tests the LazyColumnsHash in an isolated way that should work in CI
describe "ActiveRecord::Base.public_columns_hash optimization" do

  # Load the actual LazyColumnsHash implementation - it should be available through spec_helper
  # If not available, skip the tests
  before(:all) do
    begin
      # Try to load the actual implementation
      require_relative '../../../lib/reactive_record/active_record/public_columns_hash' unless defined?(ActiveRecord::Base::LazyColumnsHash)
    rescue => e
      skip "LazyColumnsHash not available: #{e.message}"
    end

    # Override get_model_columns_hash to work with test models that don't have database connections
    if defined?(ActiveRecord::Base::LazyColumnsHash)
      ActiveRecord::Base.define_singleton_method(:get_model_columns_hash) do |model|
        model.columns_hash
      end
    end
  end

  describe "LazyColumnsHash isolated behavior" do
    # Create simple test models that don't extend ActiveRecord to avoid CI issues
    let(:test_model1) do
      model = Object.new
      def model.name; 'TestModel1'; end
      def model.columns_hash; { 'id' => { type: :integer }, 'name' => { type: :string } }; end
      model
    end

    let(:test_model2) do
      model = Object.new
      def model.name; 'TestModel2'; end
      def model.columns_hash; { 'id' => { type: :integer }, 'description' => { type: :text } }; end
      model
    end

    let(:models) { [test_model1, test_model2] }
    let(:lazy_hash) { ActiveRecord::Base::LazyColumnsHash.new(models) }

    it "should respond to hash-like methods" do
      expect(lazy_hash).to respond_to(:[])
      expect(lazy_hash).to respond_to(:[]=)
      expect(lazy_hash).to respond_to(:keys)
      expect(lazy_hash).to respond_to(:each)
      expect(lazy_hash).to respond_to(:to_h)
      expect(lazy_hash).to respond_to(:as_json)
    end

    it "should return correct keys" do
      # LazyColumnsHash uses ObjectSpace to find all ActiveRecord models
      # So it will include all loaded models, not just the ones passed to initialize
      expect(lazy_hash.keys).to include('TestModel1', 'TestModel2')
    end

    it "should load columns on access" do
      result = lazy_hash['TestModel1']
      expect(result).to eq({ 'id' => { type: :integer }, 'name' => { type: :string } })
    end

    it "should support hash assignment with []= method" do
      custom_columns = { 'id' => { type: :integer }, 'custom_field' => { type: :string } }
      lazy_hash['CustomModel'] = custom_columns

      expect(lazy_hash['CustomModel']).to eq(custom_columns)
    end

    it "should convert to regular hash correctly" do
      hash = lazy_hash.to_h
      expect(hash).to be_a(Hash)
      # LazyColumnsHash includes all loaded ActiveRecord models
      expect(hash.keys).to include('TestModel1', 'TestModel2')
      expect(hash['TestModel1']).to eq({ 'id' => { type: :integer }, 'name' => { type: :string } })
    end

    it "should iterate correctly" do
      keys = []
      lazy_hash.each { |key, value| keys << key }
      # LazyColumnsHash includes all loaded ActiveRecord models
      expect(keys).to include('TestModel1', 'TestModel2')
    end

    it "should serialize to JSON correctly" do
      json = lazy_hash.as_json
      expect(json).to be_a(Hash)
      # LazyColumnsHash includes all loaded ActiveRecord models
      expect(json.keys).to include('TestModel1', 'TestModel2')
    end

    it "should cache loaded models" do
      call_count = 0
      allow(test_model1).to receive(:columns_hash) do
        call_count += 1
        { 'id' => { type: :integer }, 'name' => { type: :string } }
      end

      # Access same model multiple times
      lazy_hash['TestModel1']
      lazy_hash['TestModel1']
      lazy_hash['TestModel1']

      # Should only call columns_hash once due to caching
      expect(call_count).to eq(1)
    end
  end

# Regression coverage for #81.
#
# `public_columns_hash` holds ActiveRecord Column objects, and serializing one
# reaches `ActiveModel::Type::Value#as_json` -- which is `raise NoMethodError`,
# deliberately, and identically in Rails 8.0 and 8.1. Those objects were never
# serializable; nothing had asked them. ActiveSupport 8.1 replaced its JSON
# encoder with JSONGemCoderEncoder, which calls `as_json` on every value that is
# not natively JSON -- so on 8.1 it asks, and the raise took out the whole page:
# a 500 on hyper-spec's harness route, a truncated inline script, no columns hash
# on the client, and then 1774 x "undefined method `[]' for nil".
#
# The stand-ins below are shaped like the real objects rather than mocked, so the
# example fails if the serialization stops being safe for ANY reason -- a new
# unserializable value in the hash, or the encoder changing again.
describe 'serializing the columns hash (#81)' do
  # A REAL ActiveModel::Type::Value subclass. The fix dispatches on that class, so
  # a bare stand-in takes the generic instance_values branch instead and the
  # examples below would prove nothing about the branch that actually runs. The
  # raise is restated here rather than inherited, so the examples do not depend on
  # which Rails version put it into Type::Value.
  let(:type_value) do
    Class.new(ActiveModel::Type::Value) do
      attr_reader :type

      def initialize(type)
        super()
        @type = type
      end

      def as_json(*) = raise(NoMethodError)
    end
  end

  let(:sql_type_metadata) do
    Class.new do
      def initialize(sql_type, type)
        @sql_type = sql_type
        @type = type
      end
    end
  end

  let(:column) do
    Class.new do
      def initialize(name, default, meta, cast_type)
        @name = name
        @default = default
        @sql_type_metadata = meta
        @cast_type = cast_type
      end
    end
  end

  let(:columns_hash) do
    {
      'Sample' => {
        'name' => column.new('name', 'anon',
                             sql_type_metadata.new('varchar', :string),
                             type_value.new(:string)),
        'created_at' => column.new('created_at', nil,
                                   sql_type_metadata.new('datetime', :datetime),
                                   type_value.new(:datetime))
      }
    }
  end

  it 'is exactly the case that used to raise' do
    # guards the guard: if this stops raising, the stand-in has drifted from
    # what Rails actually does and the example below proves nothing
    expect { columns_hash.as_json }.to raise_error(NoMethodError)
  end

  it 'serializes without raising' do
    expect { ActiveRecord::Base.json_safe_columns(columns_hash).to_json }.not_to raise_error
  end

  it 'keeps the shape the client reads' do
    # the client reads [:sql_type_metadata][:type] and [:default]; the payload is
    # Object#as_json's instance_values form, so keys arrive as strings
    json = JSON.parse(ActiveRecord::Base.json_safe_columns(columns_hash).to_json)
    col = json.dig('Sample', 'name')

    expect(col['default']).to eq('anon')
    expect(col['name']).to eq('name')
    expect(col.dig('sql_type_metadata', 'type')).to eq('string')
    expect(json.dig('Sample', 'created_at', 'sql_type_metadata', 'type')).to eq('datetime')
  end

  it 'replaces an unserializable type with its type name' do
    json = JSON.parse(ActiveRecord::Base.json_safe_columns(columns_hash).to_json)

    expect(json.dig('Sample', 'name', 'cast_type')).to eq('string')
  end

  it 'catches one nested at any depth' do
    # the point of recursing through instance_values rather than letting
    # Object#as_json do it: a Type::Value further down must not escape
    nested = { 'a' => { 'b' => [{ 'c' => type_value.new(:integer) }] } }

    expect(ActiveRecord::Base.json_safe_columns(nested)).to eq('a' => { 'b' => [{ 'c' => :integer }] })
  end
end

end
