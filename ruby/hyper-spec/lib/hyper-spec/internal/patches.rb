module Opal
  # strips off stuff that confuses things when transmitting to the client
  # and prints offending code if it can't be compiled
  def self.hyperspec_compile(str, opts = {})
    compile(str, opts).gsub("// Prepare super implicit arguments\n", '')
                .delete("\n").gsub('(Opal);', '(Opal)')
                      .gsub(' try',"\ntry")
  # rubocop:disable Lint/RescueException
  # we are going to reraise it anyway, so its fine to catch EVERYTHING!
  rescue Exception => e
    puts "puts could not compile: \n\n#{str}\n\n"
    raise e
  end
  # rubocop:enable Lint/RescueException
end

module Unparser
  class Emitter
    # Emitter for send
    class Send < self
      def local_variable_clash?
        selector =~ /^[A-Z]/ ||
          local_variable_scope.local_variable_defined_for_node?(node, selector)
      end
    end
  end
end

module MethodSource
  class << self
    alias original_lines_for_before_hyper_spec lines_for
    alias original_source_helper_before_hyper_spec source_helper

    def source_helper(source_location, name = nil)
      source_location[1] = 1 if source_location[0] == '(pry)'
      original_source_helper_before_hyper_spec source_location, name
    end

    def lines_for(file_name, name = nil)
      if file_name == '(pry)'
        HyperSpec.current_pry_code_block
      else
        original_lines_for_before_hyper_spec file_name, name
      end
    end
  end
end

class Object
  def opal_serialize
    nil
  end
end

class Hash
  def opal_serialize
    parts = map do |k, v|
      ks = k.opal_serialize
      vs = v.opal_serialize
      # If any key/value can't be serialized, serialize nothing: set_local_var
      # then emits the safe "unserializable" stub for the whole variable instead
      # of producing invalid Opal like `{ => , => }`.
      return nil if ks.nil? || vs.nil?

      "#{ks} => #{vs}"
    end
    "{#{parts.join(', ')}}"
  end
end

class Array
  def opal_serialize
    parts = map(&:opal_serialize)
    # If any element can't be serialized, serialize nothing so set_local_var
    # emits the safe "unserializable" stub for the whole variable instead of
    # producing invalid Opal like `[, , ,]` (which raised Opal::SyntaxError for
    # e.g. a spec ivar holding an array of ActiveRecord objects).
    return nil if parts.any?(&:nil?)

    "[#{parts.join(', ')}]"
  end
end

[FalseClass, Float, Integer, NilClass, String, Symbol, TrueClass].each do |klass|
  klass.send(:define_method, :opal_serialize) do
    inspect
  end
end

# rubocop:disable Lint/UnifiedInteger - patch for ruby prior to 2.4
if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.4.0')
  [Bignum, Fixnum].each do |klass|
    klass.send(:define_method, :opal_serialize) do
      inspect
    end
  end
end
# rubocop:enable Lint/UnifiedInteger

class Time
  def to_opal_expression
    "Time.parse('#{inspect}')"
  end
end
