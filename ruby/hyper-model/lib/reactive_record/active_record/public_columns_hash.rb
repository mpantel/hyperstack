module Hyperstack
  define_setting :public_model_directories, [File.join('app','hyperstack','models'), File.join('app','models','public')]
  define_setting :public_columns_hash_lazy_loading, true
  define_setting :public_columns_hash_exclude_patterns, []
  define_setting :public_columns_hash_performance_logging, Rails.env.development?
end

module ActiveRecord
  # adds method to get the HyperMesh public column types
  # this works because the public folder is currently required to be eager loaded.
  class Base
    @@hyper_stack_public_columns_hash_mutex = Mutex.new
    @@hyper_stack_lazy_columns_cache = {}

    def self.public_columns_hash
      @@hyper_stack_public_columns_hash_mutex.synchronize do
        return @public_columns_hash if @public_columns_hash && Rails.env.production?

        start_time = Time.current if Hyperstack.public_columns_hash_performance_logging

        files = get_public_model_files

        if Hyperstack.public_columns_hash_lazy_loading
          @public_columns_hash = build_lazy_columns_hash(files)
        else
          @public_columns_hash = build_eager_columns_hash(files)
        end

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
      Hyperstack.public_model_directories.each do |dir|
        next unless Dir.exist?(Rails.root.join(dir))
        dir_length = Rails.root.join(dir).to_s.length + 1
        Dir.glob(Rails.root.join(dir, '**', '*.rb')).each do |file|
          require_dependency(file) # still the file is loaded to make sure for development and test env
          files << file[dir_length..-4]
        end
      end
      files
    end

    def self.filtered_descendants(files)
      descendants.select do |model|
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
      LazyColumnsHash.new(filtered_descendants(files))
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
      hash
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

    # Lazy-loading hash implementation
    class LazyColumnsHash
      def initialize(models)
        @models_by_name = models.index_by(&:name)
        @loaded_models = {}
      end

      def [](model_name)
        return @loaded_models[model_name] if @loaded_models.key?(model_name)

        model = @models_by_name[model_name]
        return nil unless model

        @loaded_models[model_name] = ActiveRecord::Base.get_model_columns_hash(model)
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
            if model_class.respond_to?(:define_attribute_methods)
              model_class.define_attribute_methods
            end
          end
        rescue => e
          # Log the error but don't break the assignment
          Rails.logger.warn "[Hyperstack] Failed to define attribute methods for #{model_name}: #{e.message}" if defined?(Rails) && Rails.logger
        end
      end

      def key?(model_name)
        @models_by_name.key?(model_name)
      end

      def keys
        @models_by_name.keys
      end

      def values
        keys.map { |key| self[key] }
      end

      def empty?
        @models_by_name.empty?
      end

      def size
        @models_by_name.size
      end
      alias_method :length, :size

      def each(&block)
        @models_by_name.keys.each do |key|
          yield(key, self[key])
        end
      end

      def each_key(&block)
        @models_by_name.keys.each(&block)
      end

      def each_value(&block)
        keys.each { |key| yield(self[key]) }
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
