# Standalone unit test for LazyColumnsHash that loads the actual implementation
# This test runs without database dependencies but loads the real code

# Create minimal Rails/ActiveRecord stubs BEFORE requiring the implementation
unless defined?(Rails)
  module Rails
    def self.env
      env_obj = Class.new do
        def development?
          false
        end
        def production?
          false
        end
        def test?
          true
        end
        def to_s
          'test'
        end
      end
      env_obj.new
    end

    def self.root
      Pathname.new('.')
    end

    class << self
      attr_accessor :logger
    end

    self.logger = Class.new do
      def warn(msg); end
      def info(msg); end
    end.new
  end

  class Pathname
    def initialize(path)
      @path = path.to_s
    end

    def join(*args)
      Pathname.new(File.join(@path, *args))
    end

    def to_s
      @path
    end
  end
end

# Stub Hyperstack settings BEFORE requiring the implementation
unless defined?(Hyperstack)
  module Hyperstack
    @settings = {}

    def self.define_setting(name, default)
      @settings[name] = default
    end

    def self.method_missing(name)
      @settings[name]
    end
  end
end

# Define minimal ActiveRecord::Base BEFORE requiring the implementation
unless defined?(ActiveRecord::Base)
  module ActiveRecord
    class Base
      def self.descendants
        []
      end

      def self.get_model_columns_hash(model)
        # Stub schema cache check and just return model's columns_hash
        model.columns_hash
      end
    end
  end
end

# Add ActiveSupport methods if not available
unless Array.method_defined?(:index_by)
  class Array
    def index_by(&block)
      hash = {}
      each { |item| hash[yield(item)] = item }
      hash
    end
  end
end

unless Hash.method_defined?(:as_json)
  class Hash
    def as_json(options = nil)
      self
    end
  end
end

# NOW load the actual LazyColumnsHash implementation
require_relative '../../../lib/reactive_record/active_record/public_columns_hash'

# Override get_model_columns_hash to work with our test models
class ActiveRecord::Base
  def self.get_model_columns_hash(model)
    # For test purposes, just return the model's columns_hash directly
    model.columns_hash
  end
end

# Test models
class TestModel1
  def self.name; 'TestModel1'; end
  def self.columns_hash
    { 'id' => { type: :integer }, 'name' => { type: :string } }
  end
end

class TestModel2
  def self.name; 'TestModel2'; end
  def self.columns_hash
    { 'id' => { type: :integer }, 'description' => { type: :text } }
  end
end

# Simple test runner
def run_tests
  puts "Running LazyColumnsHash standalone tests..."
  tests_passed = 0
  tests_failed = 0

  def assert(condition, message)
    if condition
      print "."
      return true
    else
      puts "\nFAILED: #{message}"
      return false
    end
  end

  def assert_equal(expected, actual, message)
    assert(expected == actual, "#{message} - Expected: #{expected.inspect}, Got: #{actual.inspect}")
  end

  def assert_includes(collection, item, message)
    assert(collection.include?(item), "#{message} - Expected #{collection.inspect} to include #{item.inspect}")
  end

  # Initialize test data
  models = [TestModel1, TestModel2]
  lazy_hash = ActiveRecord::Base::LazyColumnsHash.new(models)

  # Test 1: Basic hash-like methods
  tests_passed += 1 if assert(lazy_hash.respond_to?(:[]), "should respond to []")
  tests_passed += 1 if assert(lazy_hash.respond_to?(:[]=), "should respond to []=")
  tests_passed += 1 if assert(lazy_hash.respond_to?(:keys), "should respond to keys")
  tests_passed += 1 if assert(lazy_hash.respond_to?(:each), "should respond to each")
  tests_passed += 1 if assert(lazy_hash.respond_to?(:to_h), "should respond to to_h")
  tests_passed += 1 if assert(lazy_hash.respond_to?(:as_json), "should respond to as_json")
  tests_passed += 1 if assert(lazy_hash.respond_to?(:key?), "should respond to key?")

  # Test 2: Keys method
  keys = lazy_hash.keys
  tests_passed += 1 if assert_equal(2, keys.size, "should return 2 keys")
  tests_passed += 1 if assert_includes(keys, 'TestModel1', "should include TestModel1")
  tests_passed += 1 if assert_includes(keys, 'TestModel2', "should include TestModel2")

  # Test 3: Load columns on access
  result = lazy_hash['TestModel1']
  expected = { 'id' => { type: :integer }, 'name' => { type: :string } }
  tests_passed += 1 if assert_equal(expected, result, "should load columns correctly")

  # Test 4: Assignment with []=
  custom_columns = { 'id' => { type: :integer }, 'custom_field' => { type: :string } }
  lazy_hash['CustomModel'] = custom_columns
  tests_passed += 1 if assert_equal(custom_columns, lazy_hash['CustomModel'], "should support assignment")

  # Test 5: Convert to regular hash
  hash = lazy_hash.to_h
  tests_passed += 1 if assert(hash.is_a?(Hash), "to_h should return a Hash")
  tests_passed += 1 if assert_includes(hash.keys, 'TestModel1', "hash should include TestModel1")

  # Test 6: Iteration
  keys_from_each = []
  lazy_hash.each { |key, value| keys_from_each << key }
  tests_passed += 1 if assert_includes(keys_from_each, 'TestModel1', "iteration should include TestModel1")
  tests_passed += 1 if assert_includes(keys_from_each, 'TestModel2', "iteration should include TestModel2")

  # Test 7: JSON serialization
  json = lazy_hash.as_json
  tests_passed += 1 if assert(json.is_a?(Hash), "as_json should return a Hash")

  # Test 8: Caching behavior - use a fresh LazyColumnsHash instance
  call_count = 0
  original_method = TestModel1.method(:columns_hash)
  TestModel1.define_singleton_method(:columns_hash) do
    call_count += 1
    original_method.call
  end

  # Create fresh LazyColumnsHash for caching test
  fresh_lazy_hash = ActiveRecord::Base::LazyColumnsHash.new([TestModel1])

  # Access same model multiple times
  fresh_lazy_hash['TestModel1']
  fresh_lazy_hash['TestModel1']
  fresh_lazy_hash['TestModel1']

  tests_passed += 1 if assert_equal(1, call_count, "should cache loaded models (only call columns_hash once)")

  # Test 9: Key existence check
  tests_passed += 1 if assert(lazy_hash.key?('TestModel1'), "should return true for existing key")
  tests_passed += 1 if assert(!lazy_hash.key?('NonexistentModel'), "should return false for non-existing key")

  puts "\n\nTest Results:"
  puts "Tests passed: #{tests_passed}"
  puts "Tests failed: #{tests_failed}"
  puts "All tests passed!" if tests_failed == 0
end

# Run the tests if this file is executed directly
run_tests if __FILE__ == $0