# require "hyperstack/server_side_auto_require.rb" in your hyperstack initializer
# to autoload shadowed server side files that match files
# in the hyperstack directory

# Fix for Rails 6.1+ / Ruby 3.2+ compatibility
# ActiveSupport::LoggerThreadSafeLevel was removed in newer Rails versions
unless defined?(ActiveSupport::LoggerThreadSafeLevel)
  module ActiveSupport
    module LoggerThreadSafeLevel
      Logger = ::Logger
    end
  end
end

# Fix for Spring + Rails 6.1.7.10 + Ruby 3.2.9 compatibility
# Spring tries to instantiate Rails::Application directly which is abstract
if defined?(Spring) && Rails.respond_to?(:application) && Rails.application.nil?
  begin
    require Rails.root.join('config', 'application')
  rescue LoadError
    # Application file not found or already loaded
  end
end

# Rails 7 removed `config.autoloader` (Zeitwerk is the only autoloader), so the
# old `Rails.configuration.autoloader == :zeitwerk` check is false there and the
# server-side shadow files never load. Detect Zeitwerk via Rails.autoloaders.
if Rails.respond_to?(:autoloaders) && Rails.autoloaders.zeitwerk_enabled?
  Rails.autoloaders.each do |loader|
    loader.on_load do |_cpath, _value, abspath|
      ActiveSupport::Dependencies.add_server_side_dependency(abspath) do |load_path|
        loader.send(:log, "Hyperstack loading server side shadowed file: #{load_path}") if loader&.logger
        require("#{load_path}.rb")
      end
    end
  end
end

module ActiveSupport
  module Dependencies
    HYPERSTACK_DIR = "hyperstack"
    class << self
      # search the filename path from the end towards the beginning
      # for the HYPERSTACK_DIR directory.  If found, remove it from
      # the filename, and if a ruby file exists at that location then
      # add it as a dependency

      def add_server_side_dependency(file_name, loader = nil)
        path = File.expand_path(file_name.chomp(".rb"))
                   .split(File::SEPARATOR).reverse
        hs_index = path.find_index(HYPERSTACK_DIR)

        return unless hs_index # no hyperstack directory here

        new_path = (path[0..hs_index - 1] + path[hs_index + 1..-1]).reverse
        load_path = new_path.join(File::SEPARATOR)

        return unless File.exist? "#{load_path}.rb"

        yield load_path
      end
    end

    # The classic-autoloader require_or_load hook only exists before Zeitwerk;
    # Rails 7 removed ActiveSupport::Dependencies.require_or_load. On Zeitwerk the
    # loader.on_load hook above already handles shadowed server-side files, so
    # only override require_or_load when it's actually present (Rails < 7).
    if respond_to?(:require_or_load, true)
      class << self
        alias original_require_or_load require_or_load

        # before requiring_or_loading a file, first check if
        # we have the same file in the server side directory
        # and add that as a dependency
        def require_or_load(file_name, const_path = nil)
          add_server_side_dependency(file_name) { |load_path| require_dependency load_path }
          original_require_or_load(file_name, const_path)
        end
      end
    end
  end
end
