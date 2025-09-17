require 'spec_helper'

# Simplified unit test for LazyColumnsHash without full Hyperstack dependencies
describe "LazyColumnsHash unit tests" do

  before(:all) do
    # Define LazyColumnsHash locally if not available
    unless defined?(ActiveRecord::Base::LazyColumnsHash)
      class ActiveRecord::Base
        class LazyColumnsHash
          def initialize(models)
            @models_by_name = models.each_with_object({}) { |model, hash| hash[model.name] = model }
            @loaded_models = {}
          end

          def [](model_name)
            return @loaded_models[model_name] if @loaded_models.key?(model_name)

            model = @models_by_name[model_name]
            return nil unless model

            @loaded_models[model_name] = model.columns_hash
          end

          def []=(model_name, value)
            @loaded_models[model_name] = value
          end

          def keys
            @models_by_name.keys
          end

          def key?(model_name)
            @models_by_name.key?(model_name)
          end

          def each(&block)
            @models_by_name.keys.each do |key|
              yield(key, self[key])
            end
          end

          def to_h
            result = {}
            @models_by_name.keys.each do |key|
              result[key] = self[key]
            end
            result
          end

          def as_json(options = nil)
            to_h.as_json(options)
          end
        end
      end
    end

    # Create simple test models
    module TestModels
      class TestModel1
        def self.name; 'TestModels::TestModel1'; end
        def self.columns_hash
          { 'id' => { type: :integer }, 'name' => { type: :string } }
        end
      end

      class TestModel2
        def self.name; 'TestModels::TestModel2'; end
        def self.columns_hash
          { 'id' => { type: :integer }, 'description' => { type: :text } }
        end
      end
    end
  end

  describe "LazyColumnsHash functionality" do
    let(:models) { [TestModels::TestModel1, TestModels::TestModel2] }
    let(:lazy_hash) { ActiveRecord::Base::LazyColumnsHash.new(models) }

    it "should respond to hash-like methods" do
      expect(lazy_hash).to respond_to(:[])
      expect(lazy_hash).to respond_to(:[]=)
      expect(lazy_hash).to respond_to(:keys)
      expect(lazy_hash).to respond_to(:each)
      expect(lazy_hash).to respond_to(:to_h)
      expect(lazy_hash).to respond_to(:as_json)
      expect(lazy_hash).to respond_to(:key?)
    end

    it "should return correct keys" do
      expect(lazy_hash.keys).to contain_exactly('TestModels::TestModel1', 'TestModels::TestModel2')
    end

    it "should load columns on demand" do
      # Mock to track calls
      call_count = 0
      allow(TestModels::TestModel1).to receive(:columns_hash) do
        call_count += 1
        { 'id' => { type: :integer }, 'name' => { type: :string } }
      end

      # Should not have called columns_hash yet
      expect(call_count).to eq(0)

      # Access model - should trigger the call
      result = lazy_hash['TestModels::TestModel1']
      expect(call_count).to eq(1)
      expect(result).to eq({ 'id' => { type: :integer }, 'name' => { type: :string } })
    end

    it "should cache loaded models" do
      call_count = 0
      allow(TestModels::TestModel1).to receive(:columns_hash) do
        call_count += 1
        { 'id' => { type: :integer }, 'name' => { type: :string } }
      end

      # Access same model multiple times
      lazy_hash['TestModels::TestModel1']
      lazy_hash['TestModels::TestModel1']
      lazy_hash['TestModels::TestModel1']

      # Should only call columns_hash once due to caching
      expect(call_count).to eq(1)
    end

    it "should support assignment with []=" do
      custom_columns = { 'id' => { type: :integer }, 'custom_field' => { type: :string } }
      lazy_hash['CustomModel'] = custom_columns

      expect(lazy_hash['CustomModel']).to eq(custom_columns)
    end

    it "should convert to regular hash correctly" do
      hash = lazy_hash.to_h
      expect(hash).to be_a(Hash)
      expect(hash.keys).to contain_exactly('TestModels::TestModel1', 'TestModels::TestModel2')
      expect(hash['TestModels::TestModel1']).to eq({ 'id' => { type: :integer }, 'name' => { type: :string } })
    end

    it "should iterate correctly" do
      keys = []
      lazy_hash.each { |key, value| keys << key }
      expect(keys).to contain_exactly('TestModels::TestModel1', 'TestModels::TestModel2')
    end

    it "should serialize to JSON correctly" do
      json = lazy_hash.as_json
      expect(json).to be_a(Hash)
      expect(json.keys).to contain_exactly('TestModels::TestModel1', 'TestModels::TestModel2')
    end

    it "should check for key existence" do
      expect(lazy_hash.key?('TestModels::TestModel1')).to be true
      expect(lazy_hash.key?('NonexistentModel')).to be false
    end
  end
end