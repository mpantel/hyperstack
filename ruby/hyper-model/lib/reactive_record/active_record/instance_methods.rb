module ActiveRecord
  module InstanceMethods

    # if methods are missing, then they must be a column, which we look up
    # in the columns_hash.

    # For effeciency all attributes will by default have all the methods defined,
    # when the class is loaded.  See define_attribute_methods class method.
    # However a model may override the attribute methods definition, but then call
    # super.  Which will result in the method missing call.

    # When loading data from the server we do NOT want to call overridden methods
    # so we also define a _hyperstack_internal_setter_... method for each attribute
    # as well as for belongs_to relationships, server_methods, and the special
    # type and model_name methods.  See the ClassMethods module for details.

    # meanwhile in Opal 1.0 there is currently an issue where the name of the method
    # does not get passed to method_missing from super.
    # https://github.com/opal/opal/issues/2165
    # So the following hack works around that issue until its fixed.

    %x{
      Opal.orig_find_super_dispatcher = Opal.find_super_dispatcher
      Opal.find_super_dispatcher = function(obj, mid, current_func, defcheck, allow_stubs) {
        Opal.__name_of_super = mid;
        return Opal.orig_find_super_dispatcher(obj, mid, current_func, defcheck, allow_stubs)
      }
    }

    def method_missing(missing, *args, &block)
      missing ||= `Opal.__name_of_super`
      columns_hash = self.class.columns_hash
      column = columns_hash.detect { |name, *| missing =~ /^#{name}/ }

      if column
        name = column[0]
        case missing
        when /\!\z/ then @backing_record.get_attr_value(name, true)
        when /\=\z/ then @backing_record.set_attr_value(name, *args)
        when /\_changed\?\z/ then @backing_record.changed?(name)
        when /\?/ then @backing_record.get_attr_value(name, nil).present?
        else @backing_record.get_attr_value(name, nil)
        end
      elsif (columns_hash.empty? || missing.to_s.match(/^_hyperstack_internal_setter_/) ||
             (missing.to_s.match(/^[a-zA-Z_][a-zA-Z0-9_]*[=!?]?$/) && missing.to_s != 'class'))
        # If columns_hash is empty OR if this looks like a hyperstack internal method OR
        # if it looks like an attribute method, try to define attribute methods and retry

        # Special handling for _hyperstack_internal_setter_ methods - define them immediately if possible
        if missing.to_s.match(/^_hyperstack_internal_setter_(.+)$/)
          attr_name = $1
          begin
            # Define the missing internal setter method directly
            self.class.define_method("_hyperstack_internal_setter_#{attr_name}") do |val|
              @backing_record.set_attr_value(attr_name, val)
            end
            # Also define the standard setter alias
            unless self.class.method_defined?("#{attr_name}=")
              self.class.alias_method "#{attr_name}=", "_hyperstack_internal_setter_#{attr_name}"
            end
            return send(missing, *args, &block)
          rescue => e
            # If direct definition fails, continue with normal handling
            if defined?(Rails) && Rails.logger
              Rails.logger.warn "[Hyperstack] Failed to directly define internal setter #{self.class.name}.#{missing}: #{e.message}"
            else
              puts "Failed to directly define internal setter #{self.class.name}.#{missing}: #{e.message}"
            end
          end
        end

        # Special handling for basic setter methods (attr=) - define them immediately if possible
        if missing.to_s.match(/^([a-zA-Z_][a-zA-Z0-9_]*)=$/)
          attr_name = $1
          begin
            # Define the missing internal setter method if it doesn't exist
            unless self.class.method_defined?("_hyperstack_internal_setter_#{attr_name}")
              self.class.define_method("_hyperstack_internal_setter_#{attr_name}") do |val|
                @backing_record.set_attr_value(attr_name, val)
              end
            end
            # Define the setter alias
            unless self.class.method_defined?("#{attr_name}=")
              self.class.alias_method "#{attr_name}=", "_hyperstack_internal_setter_#{attr_name}"
            end
            return send(missing, *args, &block)
          rescue => e
            # If direct definition fails, continue with normal handling
            if defined?(Rails) && Rails.logger
              Rails.logger.warn "[Hyperstack] Failed to directly define setter #{self.class.name}.#{missing}: #{e.message}"
            else
              puts "Failed to directly define setter #{self.class.name}.#{missing}: #{e.message}"
            end
          end
        end

        # Special handling for basic attribute getters - define them immediately if possible
        if missing.to_s.match(/^([a-zA-Z_][a-zA-Z0-9_]*)$/) && !['class'].include?(missing.to_s)
          attr_name = missing.to_s
          begin
            # Define the missing getter method directly
            unless self.class.method_defined?(attr_name)
              self.class.define_method(attr_name) do
                @backing_record.get_attr_value(attr_name, nil)
              end
            end
            # Also define the ! version for forced reload
            unless self.class.method_defined?("#{attr_name}!")
              self.class.define_method("#{attr_name}!") do
                @backing_record.get_attr_value(attr_name, true)
              end
            end
            # Define the internal setter if it doesn't exist
            unless self.class.method_defined?("_hyperstack_internal_setter_#{attr_name}")
              self.class.define_method("_hyperstack_internal_setter_#{attr_name}") do |val|
                @backing_record.set_attr_value(attr_name, val)
              end
            end
            # Define the setter alias if it doesn't exist
            unless self.class.method_defined?("#{attr_name}=")
              self.class.alias_method "#{attr_name}=", "_hyperstack_internal_setter_#{attr_name}"
            end
            return send(missing, *args, &block)
          rescue => e
            # If direct definition fails, continue with normal handling
            if defined?(Rails) && Rails.logger
              Rails.logger.warn "[Hyperstack] Failed to directly define getter #{self.class.name}.#{missing}: #{e.message}"
            else
              puts "Failed to directly define getter #{self.class.name}.#{missing}: #{e.message}"
            end
          end
        end

        begin
          # Force columns_hash to be loaded first if it's a LazyColumnsHash
          forced_columns = self.class.columns_hash
          # Only try to define attribute methods if the class responds to it and we haven't already tried
          if self.class.respond_to?(:define_attribute_methods) && !self.class.instance_variable_get(:@defining_attribute_methods)
            self.class.instance_variable_set(:@defining_attribute_methods, true)
            begin
              self.class.define_attribute_methods
              # Mark that we've successfully defined methods to avoid repeated attempts
              self.class.instance_variable_set(:@hyperstack_methods_defined, true) unless forced_columns.empty?
            ensure
              self.class.instance_variable_set(:@defining_attribute_methods, false)
            end
            # After defining methods, try calling the method again if it now exists
            if respond_to?(missing)
              return send(missing, *args, &block)
            end
          end
        rescue => e
          # If define_attribute_methods fails, continue with normal method_missing
          if defined?(Rails) && Rails.logger
            Rails.logger.warn "[Hyperstack] Failed to auto-define attribute methods for #{self.class.name}.#{missing}: #{e.message}"
          else
            puts "Failed to auto-define attribute methods for #{self.class.name}.#{missing}: #{e.message}"
          end
        ensure
          # Make sure we clear the flag even if an exception occurs
          self.class.instance_variable_set(:@defining_attribute_methods, false) if self.class.instance_variable_get(:@defining_attribute_methods)
        end
        super
      else
        super
      end
    end

    # the system assumes that there is "virtual" model_name and type attribute so
    # we define the internal setter here.  If the user defines some other attributes
    # or uses these names no harm is done since the exact same method would have been
    # defined by the define_attribute_methods class method anyway.
    %i[model_name type].each do |attr|
      define_method("_hyperstack_internal_setter_#{attr}") do |val|
        @backing_record.set_attr_value(:model_name, val)
      end
    end

    def inspect
      "<#{model_name}:#{ReactiveRecord::Operations::Base::FORMAT % to_key} "\
      "(#{ReactiveRecord::Operations::Base::FORMAT % object_id}) "\
      "#{backing_record.inspection_details} >"
    end

    attr_reader :backing_record

    def attributes
      @backing_record.attributes
    end

    def changed_attributes
      backing_record.changed_attributes_and_values
    end

    def changes
      backing_record.changes
    end

    def initialize(hash = {})
      if hash.is_a? ReactiveRecord::Base
        @backing_record = hash
      else
        # standard active_record new -> creates a new instance, primary key is ignored if present
        # we have to build the backing record first then initialize it so associations work correctly
        @backing_record = ReactiveRecord::Base.new(self.class, {}, self)
        if self.class.inheritance_column && !hash.key?(self.class.inheritance_column)
          hash[self.class.inheritance_column] = self.class.name
        end
        @backing_record.instance_eval do
          h = {}
          hash.each do |a, v|
            a = model._dealias_attribute(a)
            h[a] = convert(a, v).itself
          end
          self.class.load_data do
            h.each do |attribute, value|
              next if attribute == :id
              @ar_instance[attribute] = value
              changed_attributes << attribute
            end
          end
        end
      end
    end

    def primary_key
      self.class.primary_key
    end

    def id
      @backing_record.get_primary_key_value
    end

    def id=(value)
      @backing_record.id = value
    end

    def id?
      id.present?
    end

    def model_name
      # in reality should return ActiveModel::Name object, blah blah
      self.class.model_name
    end

    def revert
      @backing_record.revert
    end

    def changed?(attr = nil)
      @backing_record.changed?(*attr)
    end

    def dup
      self.class.new(self.attributes)
    end

    def ==(ar_instance)
      return true  if @backing_record == ar_instance.instance_eval { @backing_record }
      return false unless ar_instance.is_a?(ActiveRecord::Base)
      return false if ar_instance.new_record?
      return false unless self.class.base_class == ar_instance.class.base_class
      id == ar_instance.id
    end

    def [](attr)
      send(attr)
    end

    def []=(attr, val)
      send("#{attr}=", val)
    end

    def itself
      # this is useful when you just want to get a handle on record instance
      # in the ReactiveRecord.load method
      id # force load of id...
      # if self.class.columns_hash.keys.include?(self.class.inheritance_column) &&
      #    (klass = self[self.class.inheritance_column]).loaded?
      #   Object.const_get(klass).new(attributes)
      # else
        self
      # end
    end

    def increment!(attr)
      load(attr).then { |current_value| update(attr => current_value + 1) }
    end

    def decrement!(attr)
      load(attr).then { |current_value| update(attr => current_value - 1) }
    end

    def load(*attributes, &block)
      first_time = true
      ReactiveRecord.load do
        results = attributes.collect { |attr| send("#{attr}#{'!' if first_time}") }
        results = yield(*results) if block
        first_time = false
        block.nil? && results.count == 1 ? results.first : results
      end
    end

    def save(opts = {}, &block)
      @backing_record.save_or_validate(true, opts.has_key?(:validate) ? opts[:validate] : true, opts[:force], &block)
    end

    def validate(opts = {}, &block)
      @backing_record.save_or_validate(false, true, opts[:force]).then do
        if block
          yield @backing_record.ar_instance
        else
          @backing_record.ar_instance
        end
      end
    end

    def valid?
      errors.reactive_empty?
    end

    def saving?
      @backing_record.saving?
    end

    def destroy(&block)
      @backing_record.destroy(&block)
    end

    def destroyed?
      @backing_record.destroyed
    end

    def new_record?
      @backing_record.new?
    end

    alias new? new_record?

    def errors
      Hyperstack::Internal::State::Variable.get(@backing_record, @backing_record)
      @backing_record.errors
    end

    def to_key
      @backing_record.object_id
    end

    def update_attribute(attr, value, &block)
      send("#{attr}=", value)
      save(validate: false, &block)
    end

    def update(attrs = {}, &block)
      attrs.each { |attr, value| send("#{attr}=", value) }
      save(&block)
    end

    def <=>(other)
      id.to_i <=> other.id.to_i
    end

    def becomes(klass)
      klass._new_without_sti_type_cast(backing_record)
    end

    def becomes!(klass)
      self[self.class.inheritance_column] = klass.name
      becomes(klass)
    end

    def cast_to_current_sti_type
      @backing_record.set_ar_instance!
    end
  end
end
