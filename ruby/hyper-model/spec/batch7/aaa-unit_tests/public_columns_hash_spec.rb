require 'spec_helper'

describe "ActiveRecord::Base.public_columns_hash optimization" do

  before(:all) do
    # Create test models in memory
    module TestModels
      class TestModel1 < ActiveRecord::Base
        def self.columns_hash
          { 'id' => { type: :integer }, 'name' => { type: :string } }
        end
        def self.name; 'TestModels::TestModel1'; end
        def self.table_name; 'test_model1s'; end
        def self.table_exists?; true; end
        def self.connection
          OpenStruct.new(schema_cache: OpenStruct.new(data_source_exists?: proc { true }))
        end
      end

      class TestModel2 < ActiveRecord::Base
        def self.columns_hash
          { 'id' => { type: :integer }, 'description' => { type: :text } }
        end
        def self.name; 'TestModels::TestModel2'; end
        def self.table_name; 'test_model2s'; end
        def self.table_exists?; true; end
        def self.connection
          OpenStruct.new(schema_cache: OpenStruct.new(data_source_exists?: proc { true }))
        end
      end

      class ExcludedModel < ActiveRecord::Base
        def self.columns_hash
          { 'id' => { type: :integer }, 'secret' => { type: :string } }
        end
        def self.name; 'TestModels::ExcludedModel'; end
        def self.table_name; 'excluded_models'; end
        def self.table_exists?; true; end
        def self.connection
          OpenStruct.new(schema_cache: OpenStruct.new(data_source_exists?: proc { true }))
        end
      end
    end
  end

  before(:each) do
    # Reset instance variables
    ActiveRecord::Base.instance_variable_set(:@public_columns_hash, nil)
    ActiveRecord::Base.instance_variable_set(:@public_columns_hash_json, nil)
    ActiveRecord::Base.instance_variable_set(:@prev_public_columns_hash, nil)

    # Reset Hyperstack settings with defaults
    Hyperstack.public_columns_hash_lazy_loading = true
    Hyperstack.public_columns_hash_exclude_patterns = []
    Hyperstack.public_columns_hash_performance_logging = false

    # Mock file structure
    allow(Dir).to receive(:exist?).and_return(true)
    allow(Dir).to receive(:glob).and_return([
      '/tmp/app/hyperstack/models/test_model1.rb',
      '/tmp/app/hyperstack/models/test_model2.rb',
      '/tmp/app/hyperstack/models/excluded_model.rb'
    ])

    # Mock require_dependency
    allow(ActiveRecord::Base).to receive(:require_dependency)

    # Mock descendants to return our test models
    allow(ActiveRecord::Base).to receive(:descendants).and_return([
      TestModels::TestModel1,
      TestModels::TestModel2,
      TestModels::ExcludedModel
    ])
  end

  describe "LazyColumnsHash behavior" do
    let(:models) { [TestModels::TestModel1, TestModels::TestModel2] }
    let(:lazy_hash) { ActiveRecord::Base::LazyColumnsHash.new(models) }

    it "should respond to hash-like methods" do
      expect(lazy_hash).to respond_to(:[])
      expect(lazy_hash).to respond_to(:keys)
      expect(lazy_hash).to respond_to(:each)
      expect(lazy_hash).to respond_to(:to_h)
      expect(lazy_hash).to respond_to(:as_json)
    end

    it "should return correct keys" do
      expect(lazy_hash.keys).to contain_exactly('TestModels::TestModel1', 'TestModels::TestModel2')
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
  end

  describe "lazy vs eager loading" do
    it "should return a LazyColumnsHash when lazy loading is enabled" do
      Hyperstack.public_columns_hash_lazy_loading = true

      result = ActiveRecord::Base.public_columns_hash
      expect(result).to be_a(ActiveRecord::Base::LazyColumnsHash)
    end

    it "should return a regular Hash when lazy loading is disabled" do
      Hyperstack.public_columns_hash_lazy_loading = false

      result = ActiveRecord::Base.public_columns_hash
      expect(result).to be_a(Hash)
      expect(result).not_to be_a(ActiveRecord::Base::LazyColumnsHash)
    end
  end

  describe "model filtering" do
    it "should exclude models based on string patterns" do
      Hyperstack.public_columns_hash_exclude_patterns = ['excluded']

      result = ActiveRecord::Base.public_columns_hash
      expect(result.keys).not_to include('TestModels::ExcludedModel')
      expect(result.keys).to include('TestModels::TestModel1')
    end

    it "should exclude models based on regex patterns" do
      Hyperstack.public_columns_hash_exclude_patterns = [/excluded/i]

      result = ActiveRecord::Base.public_columns_hash
      expect(result.keys).not_to include('TestModels::ExcludedModel')
      expect(result.keys).to include('TestModels::TestModel1')
    end

    it "should handle exclusion gracefully when no patterns match" do
      Hyperstack.public_columns_hash_exclude_patterns = ['nonexistent']

      result = ActiveRecord::Base.public_columns_hash
      expect(result.keys).to include('TestModels::TestModel1')
      expect(result.keys).to include('TestModels::TestModel2')
      expect(result.keys).to include('TestModels::ExcludedModel')
    end
  end
end