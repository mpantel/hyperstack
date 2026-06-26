require 'hyperstack/boot'
module Hyperstack
  def self.naming_convention
    :camelize_params
  end
end
if RUBY_ENGINE == 'opal'
  require 'hyperstack/native_wrapper_compatibility' # needs to be early...
  require 'hyperstack/deprecation_warning'
  require 'hyperstack/string'
  require 'hyperstack/client_stubs'
  require 'hyperstack/context'
  require 'hyperstack/js_imports'
  require 'hyperstack/on_client'
  require 'hyperstack/active_support_string_inquirer.rb'
  require 'hyperstack_env'
  require 'hyperstack/hotloader/stub'
  require 'promise'
  # Opal < 1.8 has no Opal::Raw; alias it to the legacy JS module so code can use
  # Opal::Raw uniformly. On Opal 1.8+ Opal::Raw already exists (corelib defines it,
  # and the full module is imported server side), so defined? is true here and we
  # never require 'js' (which would emit the 1.8 deprecation warning).
  unless defined?(::Opal::Raw)
    require 'js'
    ::Opal.const_set(:Raw, ::JS)
  end
  # uncommenting these lines breaks prerendering
  # require 'opal-browser'
else
  require 'opal'

  # Opal 1.8 deprecates implicit x-strings (embedded JS via backticks / %x{}),
  # warning per file to add a `# backtick_javascript: true` magic comment. This
  # codebase (and apps built on it) embed JS via backticks pervasively, so opt in
  # globally rather than annotating every file. Patch the compiler directly so
  # EVERY compile path treats backticks as JS without warning -- not just the
  # asset pipeline (Opal::Config) but also ad-hoc Opal.compile calls (e.g.
  # hyper-spec's expect_evaluate_ruby). No-op on Opal < 1.8. The per-file
  # magic-comment migration remains the eventual Opal 2.0 task.
  if defined?(Opal::Compiler) && Opal::Compiler.method_defined?(:backtick_javascript_or_warn?)
    Opal::Compiler.prepend(Module.new do
      def backtick_javascript_or_warn?
        true
      end
    end)
  end

  # because promises and features in opal-browsers are used everywhere we load them here
  require 'opal-browser'

  # We need opal-rails to be loaded for Gem code to be properly included by sprockets.
  begin
    require 'opal-rails' if defined? Rails
  rescue LoadError
    puts "****** WARNING: To use Hyperstack with Rails you must include the 'opal-rails' gem in your gem file."
  end
  require 'hyperstack/config_settings'
  require 'hyperstack/context'
  require 'hyperstack/imports'
  require 'hyperstack/js_imports'
  require 'hyperstack/client_readers'
  require 'hyperstack/on_client'

  if defined? Rails
    require 'hyperstack/rail_tie'
  end
  require 'hyperstack/active_support_string_inquirer.rb' unless defined? ActiveSupport
  require 'hyperstack/env'
  require 'hyperstack/on_error'
  Hyperstack.define_setting :hotloader_port, 25222
  Hyperstack.define_setting :hotloader_ping, nil
  Hyperstack.define_setting :hotloader_ignore_callback_mapping, false
  Hyperstack.import 'opal', gem: true

  # Cross-version access to Opal's raw-JS module. Opal 1.8 renamed JS -> Opal::Raw
  # and warns when the 'js' stdlib is required. Import the non-deprecated
  # 'opal/raw' on 1.8+ (silent); on older Opal, Opal::Raw is aliased to JS in the
  # client branch above. Decided here (server side) because Opal can't compile a
  # `require 'opal/raw'` on versions where that file doesn't exist.
  if Gem::Version.new(Opal::VERSION) >= Gem::Version.new('1.8.0')
    Hyperstack.import 'opal/raw', client_only: true
  end

  # because promises and features in opal-browsers are used everywhere we load them here
  Hyperstack.import 'promise', client_only: true
  Hyperstack.import 'browser', client_only: true
  Hyperstack.import 'browser/delay', client_only: true
  Hyperstack.import 'browser/interval', client_only: true

  Hyperstack.import 'hyperstack-config', gem: true
  Hyperstack.import 'hyperstack/autoloader'
  Hyperstack.import 'hyperstack/autoloader_starter'
  # based on the environment pick the directory containing the file with the matching
  # value for the client.  This avoids use of ERB for builds outside of sprockets environment
  Opal.append_path(File.expand_path("../hyperstack/environment/#{Hyperstack.env}/", __FILE__))
  Opal.append_path(File.expand_path('../', __FILE__))
end
