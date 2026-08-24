ENV["RAILS_ENV"] ||= 'test'

require 'opal'
require 'opal-jquery'
# require 'mini_racer'

begin
  require File.expand_path('../test_app/config/environment', __FILE__)
rescue LoadError
  puts 'Could not load test application. Please ensure you have run `bundle exec rake test_app`'
end
require 'rspec/rails'
require 'hyper-spec'
require 'pry'
require 'timecop'

RSpec.configure do |config|
  config.color = true
  config.fail_fast = ENV['FAIL_FAST'] || false
  config.fixture_path = File.join(File.expand_path(File.dirname(__FILE__)), "fixtures")
  config.infer_spec_type_from_file_location!
  config.mock_with :rspec
  config.raise_errors_for_deprecations!

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, comment the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  config.before :each do
    Rails.cache.clear
  end

  # config.before :suite do
  #   MiniRacer_Backup = MiniRacer
  #   Object.send(:remove_const, :MiniRacer)
  # end

  # config.around(:each, :prerendering_on) do |example|
  #   MiniRacer = MiniRacer_Backup
  #   example.run
  #   Object.send(:remove_const, :MiniRacer)
  # end

  config.filter_run_including focus: true
  config.filter_run_excluding opal: true
  config.run_all_when_everything_filtered = true

  # Fail tests on JavaScript errors in Chrome Headless
  class JavaScriptError < StandardError; end

  config.after(:each, js: true) do
    logs = page.driver.browser.logs.get(:browser)
    errors = logs.select { |e| e.level == "SEVERE" && e.message.present? }
                 .map { |m| m.message.gsub(/\\n/, "\n") }.to_a
    if client_options[:deprecation_warnings] == :on
      warnings = logs.select { |e| e.level == "WARNING" && e.message.present? }
                     .map { |m| m.message.gsub(/\\n/, "\n") }.to_a
      puts "\033[0;33;1m\nJavascript client console warnings:\n\n" + warnings.join("\n\n") + "\033[0;30;21m" if warnings.present?
    end
    unless client_options[:raise_on_js_errors] == :off
      raise JavaScriptError, errors.join("\n\n") if errors.present?
    end
  end

  HyperSpec::Helpers.alias_method :on_client, :before_mount
end

# Stubbing the React calls so we can test outside of Opal
# module React
#   class State
#     class << self
#       def reset!
#         @states = nil
#       end
#
#       def get_state(from, key)
#         states[from] ||= {}
#         states[from][key.to_s]
#       end
#
#       def set_state(from, key, value)
#         states[from] ||= {}
#         states[from][key.to_s] = value
#       end
#
#       def states
#         @states ||= {}
#       end
#     end
#   end
# end

# React <= 16 interpolated its warnings before handing them to console.error, so
# Chrome captured one readable sentence. React 17 passes the *format string* and
# its arguments separately instead:
#
#   "Warning: Failed %s type: %s%s"  "prop"  "In component `Foo` ..."  " at eval ..."
#
# Same information, different shape. Re-interpolating here lets the assertions be
# written once, against the readable form, on either React version -- rather than
# teaching every expectation about both. (#51)
def console_messages
  page.driver.browser.logs.get(:browser)
      .map { |m| expand_console_format(m.message.gsub(/\\n/, "\n")) }
      .to_a.join("\n")
end

def expand_console_format(message)
  return message unless message.include?('%s')

  segments = message.scan(/"((?:[^"\\]|\\.)*)"/m).flatten
  return message if segments.size < 2

  format_str, *args = segments
  expanded = format_str.dup
  args.each { |arg| expanded = expanded.sub('%s', arg) }
  "#{message.split('"').first}#{expanded}"
end

# The React the browser actually loaded. Which React a cell gets is decided by
# react-rails (2.x bundles 16.x, 2.7.x bundles 17.0.2, 3.3 bundles 18.2) or, on
# the esbuild pipeline, by npm -- so asking the page is the only reliable answer.
# Used where React changed observable behaviour rather than API. (#51)
def react_version_major
  @react_version_major ||= evaluate_ruby('`React.version`').to_s.split('.').first.to_i
end
