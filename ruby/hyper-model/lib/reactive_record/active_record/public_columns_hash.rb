require_relative '../constant_gate'

module Hyperstack
  define_setting :public_model_directories, [File.join('app','hyperstack','models'), File.join('app','models','public')]
  define_setting :public_columns_hash_lazy_loading, true
  define_setting :public_columns_hash_exclude_patterns, []
  define_setting :public_columns_hash_performance_logging, Rails.env.development?
end

# Ensure critical base classes are loaded before lazy-loading initialization
# This prevents "uninitialized constant" errors during JavaScript compilation
if RUBY_ENGINE == 'opal'
  begin
    # Pre-load commonly used base classes to prevent loading order issues
    require 'hyperstack/component' if defined?(Hyperstack) && !defined?(Hyperstack::Component)

    # Ensure these paths exist and can be loaded if they're available
    base_classes_paths = [
      'components/base_classes',
      'app/hyperstack/components/base_classes',
      'app/hyperstack/components/hyper_component'
    ]

    base_classes_paths.each do |path|
      begin
        require path
      rescue LoadError
        # It's okay if these don't exist, just continue
        next
      rescue => e
        Rails.logger.warn "[Hyperstack] Failed to pre-load #{path}: #{e.message}" if defined?(Rails) && Rails.logger
      end
    end
  rescue => e
    Rails.logger.warn "[Hyperstack] Failed to pre-load base classes: #{e.message}" if defined?(Rails) && Rails.logger
  end
end

module ActiveRecord
  # adds method to get the HyperMesh public column types
  # this works because the public folder is currently required to be eager loaded.
  class Base
    @@hyper_stack_public_columns_hash_mutex = Mutex.new
    @@hyper_stack_lazy_columns_cache = {}

    def self.public_columns_hash
      @@hyper_stack_public_columns_hash_mutex.synchronize do
        # CRITICAL FIX: Cache in test/dev too, not just production
        # Rebuilding on every call loses @models_by_name cache in LazyColumnsHash
        # causing repeated Object.const_get() calls and timing issues
        return @public_columns_hash if @public_columns_hash

        start_time = Time.current if Hyperstack.public_columns_hash_performance_logging

        # Ensure basic requirements are loaded before attempting to build the hash
        begin
          # Pre-load critical classes to prevent loading order issues
          require 'active_record' unless defined?(ActiveRecord)

          # Ensure ActiveRecord::Base is available
          unless defined?(ActiveRecord::Base)
            Rails.logger.warn "[Hyperstack] ActiveRecord::Base not available during public_columns_hash initialization" if defined?(Rails) && Rails.logger
            return {}
          end
        rescue => e
          Rails.logger.error "[Hyperstack] Failed to ensure ActiveRecord availability: #{e.message}" if defined?(Rails) && Rails.logger
          return {}
        end

        files = get_public_model_files

        if Hyperstack.public_columns_hash_lazy_loading
          @public_columns_hash = build_lazy_columns_hash(files)
        else
          @public_columns_hash = build_eager_columns_hash(files)
        end

        # Ensure we return something valid even if initialization partially fails
        @public_columns_hash ||= {}

        if Hyperstack.public_columns_hash_performance_logging
          total_time = Time.current - start_time
          model_count = @public_columns_hash.respond_to?(:keys) ? @public_columns_hash.keys.size : filtered_descendants(files).size
          Rails.logger.info "[Hyperstack] public_columns_hash loaded #{model_count} models in #{(total_time * 1000).round(2)}ms (lazy: #{Hyperstack.public_columns_hash_lazy_loading})"
        end

        @public_columns_hash
      end
    end

    private

    def self.get_public_model_files
      files = []
      file_paths = {}

      Hyperstack.public_model_directories.each do |dir|
        next unless Dir.exist?(Rails.root.join(dir))
        dir_length = Rails.root.join(dir).to_s.length + 1
        Dir.glob(Rails.root.join(dir, '**', '*.rb')).each do |file|
          # TRUE LAZY LOADING: Don't require_dependency here
          # Let files be loaded on-demand when first accessed
          relative_path = file[dir_length..-4]
          files << relative_path
          file_paths[relative_path] = file
        end
      end

      # Store file paths for lazy loading
      @model_file_paths = file_paths

      files
    end

    def self.filtered_descendants(files)
      descendants.compact.select do |model|
        next false unless model && model.respond_to?(:name) && model.name
        next false unless files.include?(model.name.underscore)
        next false if model.name.underscore == 'application_record'
        next false if excluded_model?(model)
        next false unless model.table_exists? rescue false # Skip models without tables
        true
      end
    end

    def self.excluded_model?(model)
      model_name = model.name.underscore
      Hyperstack.public_columns_hash_exclude_patterns.any? do |pattern|
        case pattern
        when String
          model_name.include?(pattern)
        when Regexp
          model_name =~ pattern
        else
          false
        end
      end
    end

    def self.build_lazy_columns_hash(files)
      # Return a lazy-loading hash that only loads columns when accessed
      # Pass file paths for on-demand loading of models

      # Load policies for all models (even those not yet loaded)
      # Policies control access and must be loaded upfront for security
      load_policies_for_files(files)

      # TRUE LAZY LOADING FIX: Don't call filtered_descendants which loads all models upfront
      # Pass empty array - models will be loaded on-demand when accessed
      LazyColumnsHash.new([], files, @model_file_paths)
    end

    def self.load_policies_for_files(files)
      # For each model file, try to load its corresponding policy
      # This ensures policies are loaded even with lazy model loading
      files.each do |file_path|
        # Convert file path to model name (e.g., "user" => "User", "calls/project" => "Calls::Project")
        model_name = file_path.camelize
        policy_name = "#{model_name}Policy"

        begin
          # Try to load the policy if it exists
          # This uses Rails autoloading which will search in app/policies
          policy_name.constantize
        rescue NameError, LoadError => e
          # Policy doesn't exist, which is fine - not all models need policies
          # Only log if it's an actual error (not just "uninitialized constant")
          unless e.message.include?("uninitialized constant") || e.message.include?("Unable to autoload constant")
            Rails.logger.debug "[Hyperstack] Could not load policy #{policy_name}: #{e.message}" if defined?(Rails) && Rails.logger && Hyperstack.public_columns_hash_performance_logging
          end
        end
      end
    end

    def self.build_eager_columns_hash(files)
      hash = {}
      filtered_descendants(files).each do |model|
        begin
          hash[model.name] = get_model_columns_hash(model)
        rescue => e
          Rails.logger.warn "[Hyperstack] Failed to load columns for #{model.name}: #{e.message}" if Hyperstack.public_columns_hash_performance_logging
        end
      end
      # Extend the hash with our custom []= method to handle dynamic model additions
      hash.extend(PublicColumnsHashExtension)
    end

    def self.get_model_columns_hash(model)
      # Use schema cache if available to avoid database queries
      if model.connection.schema_cache.data_source_exists?(model.table_name)
        model.columns_hash
      else
        {}
      end
    rescue
      {}
    end

    # Extension module to add dynamic model handling to regular Hash objects
    module PublicColumnsHashExtension
      def []=(model_name, value)
        result = super(model_name, value)

        # When a model is manually added (e.g., in tests), ensure its attribute methods are defined
        # This prevents the "undefined method `_hyperstack_internal_setter_*`" errors
        begin
          if Object.const_defined?(model_name)
            model_class = Object.const_get(model_name)
            # Only call define_attribute_methods if we're not already in the middle of defining them
            # This prevents infinite recursion
            if model_class.respond_to?(:define_attribute_methods) &&
               model_class.respond_to?(:table_exists?) &&
               !model_class.instance_variable_get(:@defining_attribute_methods)
              # Only define attribute methods if the model has a proper table
              has_table = begin
                model_class.table_exists?
              rescue
                false
              end
              if has_table
                Rails.logger.info "[Hyperstack] Calling define_attribute_methods for #{model_name}" if defined?(Rails) && Rails.logger
                model_class.instance_variable_set(:@defining_attribute_methods, true)
                begin
                  model_class.define_attribute_methods
                ensure
                  model_class.instance_variable_set(:@defining_attribute_methods, false)
                end
              else
                Rails.logger.warn "[Hyperstack] Skipping define_attribute_methods for #{model_name} - table does not exist" if defined?(Rails) && Rails.logger
              end
            else
              Rails.logger.info "[Hyperstack] Skipping define_attribute_methods for #{model_name} (already defining: #{model_class.instance_variable_get(:@defining_attribute_methods)})" if defined?(Rails) && Rails.logger
            end
          end
        rescue => e
          # Log the error but don't break the assignment
          Rails.logger.warn "[Hyperstack] Failed to define attribute methods for #{model_name}: #{e.message}" if defined?(Rails) && Rails.logger
        end

        result
      end
    end

    # Lazy-loading hash implementation with on-demand file loading
    class LazyColumnsHash
      def initialize(models, file_paths = [], file_path_map = {})
        # More defensive initialization with better error handling
        begin
          if models.nil?
            @models_by_name = {}
            Rails.logger.warn "[Hyperstack] LazyColumnsHash initialized with nil models" if defined?(Rails) && Rails.logger
          else
            valid_models = models.compact.select do |m|
              m && m.respond_to?(:name) && m.name && !m.name.empty?
            end
            @models_by_name = valid_models.index_by(&:name)
            Rails.logger.info "[Hyperstack] LazyColumnsHash initialized with #{@models_by_name.size} loaded models" if defined?(Rails) && Rails.logger && Hyperstack.public_columns_hash_performance_logging
          end
        rescue => e
          Rails.logger.error "[Hyperstack] Failed to initialize LazyColumnsHash: #{e.message}" if defined?(Rails) && Rails.logger
          @models_by_name = {}
        end

        # Store file paths for on-demand loading
        @file_paths = file_paths || []
        @file_path_map = file_path_map || {}
        @loaded_models = {}
        @initialization_complete = true

        Rails.logger.info "[Hyperstack] LazyColumnsHash: #{@models_by_name.size} models loaded, #{@file_paths.size - @models_by_name.size} available for lazy loading" if defined?(Rails) && Rails.logger && Hyperstack.public_columns_hash_performance_logging
      end

      def [](model_name)
        # Return immediately if already loaded
        return @loaded_models[model_name] if @loaded_models.key?(model_name)

        # Ensure we're properly initialized before proceeding
        unless @initialization_complete
          Rails.logger.warn "[Hyperstack] LazyColumnsHash accessed before initialization complete" if defined?(Rails) && Rails.logger
          return nil
        end

        # Defensive check to prevent nil reference errors
        return nil if model_name.nil? || model_name.to_s.empty?

        # SIMPLIFIED: Call get_or_load_model directly (it has its own cache check)
        # This matches the patch's simpler approach
        model = get_or_load_model(model_name)
        return nil unless model

        # Load and cache the columns hash
        @loaded_models[model_name] = load_columns_for_model(model, model_name)
      rescue => e
        # If there's an error loading columns, return nil so || {} fallback works
        Rails.logger.warn "[Hyperstack] Failed to load columns for #{model_name}: #{e.message}" if defined?(Rails) && Rails.logger
        nil
      end

      def []=(model_name, value)
        @loaded_models[model_name] = value

        # When a model is manually added (e.g., in tests), ensure its attribute methods are defined
        # This prevents the "undefined method `_hyperstack_internal_setter_*`" errors
        begin
          if Object.const_defined?(model_name)
            model_class = Object.const_get(model_name)
            # Only call define_attribute_methods if we're not already in the middle of defining them
            # This prevents infinite recursion
            if model_class.respond_to?(:define_attribute_methods) &&
               model_class.respond_to?(:table_exists?) &&
               !model_class.instance_variable_get(:@defining_attribute_methods)
              # Only define attribute methods if the model has a proper table
              has_table = begin
                model_class.table_exists?
              rescue
                false
              end
              if has_table
                model_class.instance_variable_set(:@defining_attribute_methods, true)
                begin
                  model_class.define_attribute_methods
                ensure
                  model_class.instance_variable_set(:@defining_attribute_methods, false)
                end
              end
            end
          end
        rescue => e
          # Log the error but don't break the assignment
          Rails.logger.warn "[Hyperstack] Failed to define attribute methods for #{model_name}: #{e.message}" if defined?(Rails) && Rails.logger
        end
      end

      def key?(model_name)
        # Check if model is loaded OR if file exists for it
        model_name_str = model_name.to_s
        return true if @models_by_name.key?(model_name_str)

        # Explicitly registered by server-side code (specs add models this way).
        return true if @loaded_models.key?(model_name_str)

        # A file in a public model directory makes the name legitimate whether or
        # not it has been loaded yet -- that is the whole point of lazy loading.
        return true if @file_paths.any? { |fp| fp == model_name_str.underscore }

        # Otherwise the name only counts if the constant is *genuinely* loaded.
        # `Object.const_defined?` was used here, which under Zeitwerk is true for
        # every autoloadable class in the app -- so `get_model`, which gates on
        # this, would accept any client string and then autoload it. (#60)
        ReactiveRecord::ConstantGate.loaded?(model_name_str)
      end

      def keys
        # Return all possible model names (from files + already loaded + pre-initialized)
        file_model_names = @file_paths.map { |fp| fp.camelize }

        # PERFORMANCE FIX: Use ActiveRecord::Base.descendants instead of ObjectSpace
        # ObjectSpace.each_object(Class) iterates through EVERY object in memory (millions!)
        # ActiveRecord::Base.descendants is O(1) - Rails maintains this list internally
        # This fix reduces keys() from 10+ minutes to milliseconds
        loaded_model_names = begin
          ActiveRecord::Base.descendants.map(&:name).compact
        rescue
          # Fallback to empty array if descendants not available
          []
        end

        # Also include pre-loaded models from initialization (for backward compatibility)
        preloaded_model_names = @models_by_name.keys

        (file_model_names + loaded_model_names + preloaded_model_names).uniq
      end

      def values
        keys.map { |key| self[key] }.compact
      end

      def empty?
        # TRUE LAZY LOADING FIX: Check file paths, not just pre-loaded models
        @file_paths.empty?
      end

      def size
        # TRUE LAZY LOADING FIX: Count available model files, not just pre-loaded models
        @file_paths.size
      end
      alias_method :length, :size

      def each(&block)
        # TRUE LAZY LOADING FIX: Iterate over all available models (from files), not just pre-loaded
        keys.each do |key|
          value = self[key]
          yield(key, value) if value
        end
      end

      def each_key(&block)
        # TRUE LAZY LOADING FIX: Iterate over all available models (from files), not just pre-loaded
        keys.each(&block)
      end

      def each_value(&block)
        # TRUE LAZY LOADING FIX: Iterate over all available models (from files), not just pre-loaded
        keys.each do |key|
          value = self[key]
          yield(value) if value
        end
      end

      def to_h
        # TRUE LAZY LOADING FIX: Include all available models (from files), not just pre-loaded
        result = {}
        keys.each do |key|
          value = self[key]
          result[key] = value if value
        end
        result
      end

      def as_json(options = nil)
        to_h.as_json(options)
      end

      def inspect
        "#<#{self.class.name}:#{object_id} #{to_h.inspect}>"
      end

      def respond_to_missing?(method_name, include_private = false)
        {}.respond_to?(method_name, include_private) || super
      end

      def method_missing(method_name, *args, &block)
        if {}.respond_to?(method_name)
          to_h.send(method_name, *args, &block)
        else
          super
        end
      end

      private

      # Get model constant, loading file if necessary
      def get_or_load_model(model_name)
        model_name_str = model_name.to_s

        # CRITICAL: Check cache first to avoid repeated const lookups
        return @models_by_name[model_name_str] if @models_by_name[model_name_str]

        # Check if constant already defined
        if Object.const_defined?(model_name_str)
          model = Object.const_get(model_name_str)
          # Cache it immediately to avoid repeated lookups
          @models_by_name[model_name_str] = model if model < ActiveRecord::Base
          return @models_by_name[model_name_str]
        end

        # Try to load the model file
        file_path = find_file_path_for_model(model_name_str)
        if file_path
          Rails.logger.info "[Hyperstack] Loading model file for #{model_name_str}: #{file_path}" if defined?(Rails) && Rails.logger && Hyperstack.public_columns_hash_performance_logging

          begin
            require_dependency(file_path)

            # Check if constant is now defined
            if Object.const_defined?(model_name_str)
              model = Object.const_get(model_name_str)
              if model < ActiveRecord::Base
                # Cache the loaded model to avoid repeated const lookups
                @models_by_name[model_name_str] = model
                return model
              end
            end
          rescue => e
            Rails.logger.warn "[Hyperstack] Failed to load model #{model_name_str}: #{e.message}" if defined?(Rails) && Rails.logger
            return nil
          end
        end

        nil
      end

      # Find file path for a model name
      def find_file_path_for_model(model_name)
        return nil unless @file_path_map

        # Try exact match first
        underscore_name = model_name.underscore
        return @file_path_map[underscore_name] if @file_path_map[underscore_name]

        # Try namespace variations (e.g., Rescom::User -> rescom/user)
        @file_path_map.each do |relative_path, full_path|
          if relative_path.camelize == model_name || relative_path.classify == model_name
            return full_path
          end
        end

        nil
      end

      # Load columns hash for a model
      def load_columns_for_model(model, model_name)
        # Ensure attribute methods are defined
        begin
          if model.respond_to?(:define_attribute_methods) &&
             model.respond_to?(:table_exists?) &&
             !model.instance_variable_get(:@defining_attribute_methods)
            # Only define attribute methods if the model has a proper table
            has_table = begin
              model.table_exists?
            rescue
              false
            end
            if has_table
              Rails.logger.info "[Hyperstack] Defining attribute methods for #{model_name}" if defined?(Rails) && Rails.logger && Hyperstack.public_columns_hash_performance_logging
              model.instance_variable_set(:@defining_attribute_methods, true)
              begin
                model.define_attribute_methods
              ensure
                model.instance_variable_set(:@defining_attribute_methods, false)
              end
            else
              Rails.logger.warn "[Hyperstack] Skipping define_attribute_methods for #{model_name} - table does not exist" if defined?(Rails) && Rails.logger
            end
          end
        rescue => e
          Rails.logger.warn "[Hyperstack] Failed to define attribute methods for #{model_name}: #{e.message}" if defined?(Rails) && Rails.logger
        end

        # Get columns hash
        ActiveRecord::Base.get_model_columns_hash(model)
      end
    end

    @@hyper_stack_public_columns_hash_as_json_mutex = Mutex.new
    def self.public_columns_hash_as_json
      @@hyper_stack_public_columns_hash_as_json_mutex.synchronize do
        return @public_columns_hash_json if @public_columns_hash_json && Rails.env.production?
        pch = public_columns_hash
        return @public_columns_hash_json if @prev_public_columns_hash == pch
        @prev_public_columns_hash = pch
        @public_columns_hash_json = pch.to_json
      end
    end
  end
end
