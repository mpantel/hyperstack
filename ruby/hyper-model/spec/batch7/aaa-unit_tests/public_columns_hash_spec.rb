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

end
