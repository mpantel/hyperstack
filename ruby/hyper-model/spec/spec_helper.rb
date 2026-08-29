# Stream output live instead of dumping it when the process exits. Ruby's own IO
# buffering (not glibc's, so `stdbuf` has NO effect here) holds output until ~8KB
# or exit whenever stdout is not a tty -- true of every CI job, which is why a
# progressing run can look hung for minutes. (#69)
$stdout.sync = true
$stderr.sync = true

ENV["RAILS_ENV"] ||= 'test'

require 'hyper-spec'
require 'pry'
require 'opal-browser'
# require 'mini_racer'

begin
  require File.expand_path('../test_app/config/environment', __FILE__)
rescue LoadError
  puts 'Could not load test application. Please ensure you have run `bundle exec rake test_app`'
end
require 'rspec/rails'
require 'timecop'
require "rspec/wait"

Dir["./spec/support/**/*.rb"].sort.each { |f| require f }

# Fix for signal trap bug where previous_trap can be a string instead of a callable
# This affects multiple gems including pusher-fake and selenium-webdriver
module Signal
  class << self
    alias_method :original_trap, :trap

    def trap(signal, command = nil, &block)
      previous_trap = if block_given?
        original_trap(signal, &block)
      else
        original_trap(signal, command)
      end

      # Return the previous trap handler, ensuring it's properly wrapped
      if previous_trap.is_a?(String)
        previous_trap
      elsif previous_trap.respond_to?(:call)
        previous_trap
      else
        "DEFAULT"
      end
    end
  end
end

# Additional fix for pusher-fake specifically
class Object
  def self.monkey_patch_pusher_fake!
    return unless defined?(PusherFake::Server::ChainTrapHandlers)

    PusherFake::Server::ChainTrapHandlers.module_eval do
      def trap(*arguments)
        previous_trap = super do
          yield
          # Only call previous_trap if it's callable (not "DEFAULT" or "IGNORE" strings)
          previous_trap.call if previous_trap.respond_to?(:call)
        end
      end
    end
  end
end

RSpec.configure do |config|

  if config.formatters.empty?
    module Hyperstack
      def self.log_import(s)
        # turn off import logging unless in verbose mode
      end
    end
  end

  # config.before :suite do
  #   # grab the prerendered .js file, for debugging purposes
  #   class MiniRacer::Context
  #     alias original_eval eval
  #     def eval(str, options = nil)
  #       original_eval str, options
  #     rescue Exception => e
  #       File.write('react_prerendering_src.js', str) rescue nil
  #       raise e
  #     end
  #   end
  #   MiniRacer_Backup = MiniRacer
  #   Object.send(:remove_const, :MiniRacer)
  # end

  # config.around(:each, :prerendering_on) do |example|
  #   MiniRacer = MiniRacer_Backup
  #   example.run
  #   Object.send(:remove_const, :MiniRacer)
  # end

  config.color = true
  config.fail_fast = ENV['FAIL_FAST'] || false
  fixtures_dir = File.join(File.expand_path(File.dirname(__FILE__)), "fixtures")
  # rspec-rails 7 (Rails 7) removed fixture_path= in favour of fixture_paths= (array).
  # respond_to? rather than a Rails version check, so this works on both eras. (#51)
  if config.respond_to?(:fixture_paths=)
    config.fixture_paths = [fixtures_dir]
  else
    config.fixture_path = fixtures_dir
  end
  config.infer_spec_type_from_file_location!
  config.mock_with :rspec
  config.raise_errors_for_deprecations!

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, comment the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  config.after :each do
    Rails.cache.clear
  end

  config.after(:each) do |example|
    unless example.exception
      #Object.send(:remove_const, :Application) rescue nil
      ObjectSpace.each_object(Class).each do |klass|
        if klass < Hyperstack::Regulation
          klass.instance_variables.each { |v| klass.instance_variable_set(v, nil) }
        end
      end
      PusherFake::Channel.reset if defined? PusherFake
    end
  end

  config.filter_run_including focus: true
  config.filter_run_excluding opal: true
  config.run_all_when_everything_filtered = true
end

FACTORY_BOT = false

#require 'rails_helper'
require 'rspec'
require 'rspec/expectations'
begin
  require 'factory_bot_rails'
rescue LoadError
end
require 'shoulda/matchers'
require 'database_cleaner'
require 'capybara/rspec'
require 'capybara/rails'
# require 'support/component_helpers'
# require 'selenium-webdriver'

def policy_allows_all
  stub_const 'TestApplication', Class.new
  stub_const 'TestApplicationPolicy', Class.new
  TestApplicationPolicy.class_eval do
    always_allow_connection
    regulate_all_broadcasts { |policy| policy.send_all }
    allow_change(to: :all, on: [:create, :update, :destroy]) { true }
  end
end


module React
  module IsomorphicHelpers
    def self.xxxload_context(ctx, controller, name = nil)
      @context = Context.new("#{controller.object_id}-#{Time.now.to_i}", ctx, controller, name)
    end
  end
end

#Capybara.default_max_wait_time = 4.seconds

Capybara.server = :puma

# The following is deprecated and replaced by the above... just make sure it works
# before removing
# Capybara.server { |app, port|
#   require 'puma'
#   Puma::Server.new(app).tap do |s|
#     s.add_tcp_listener Capybara.server_host, port
#   end.run.join
# }

module WaitForAjax

  def wait_for_ajax
    Timeout.timeout(Capybara.default_max_wait_time) do
      begin
        sleep 0.25
      end until finished_all_ajax_requests?
    end
  end

  def running?
    jscode = <<-CODE
    (function() {
      if (typeof Opal !== "undefined" && Opal.Hyperstack !== undefined) {
        try {
          return Opal.Hyperstack.$const_get("HTTP")["$active?"]();
        } catch(err) {
          if (typeof jQuery !== "undefined" && jQuery.active !== undefined) {
            return jQuery.active > 0;
          }
        }
      } else if (typeof jQuery !== "undefined" && jQuery.active !== undefined) {
        return jQuery.active > 0;
      } else {
        return false;
      }
    })();
    CODE
    page.evaluate_script(jscode)
  rescue Exception => e
    puts "wait_for_ajax failed while testing state of jQuery.active: #{e}"
  end

  def finished_all_ajax_requests?
    unless running?
      sleep 0.25 # this was 1 second, not sure if its necessary to be so long...
      !running?
    end
  rescue Capybara::NotSupportedByDriverError
    true
  rescue Exception => e
    e.message == "jQuery or Hyperstack::HTTP is not defined"
  end

end

module CheckErrors
  def check_errors
    logs = page.driver.browser.logs.get(:browser)
    errors = logs.select { |e| e.level == "SEVERE" && e.message.present? }
                .map { |m| m.message.gsub(/\\n/, "\n") }.to_a
    puts "WARNING - FOUND UNEXPECTED ERRORS #{errors}" if errors.present?
  end
end

# Broadcasting to a client that has not finished the pusher handshake silently
# loses the message. (#70)
#
# `Hyperstack::Connection` has two states for a channel:
#
#   session NOT NULL -> the client has `open`ed the connection but has not yet
#                       completed `connect_to_transport`. send_to_channel takes
#                       the QUEUE path (`Connection.pending_for`).
#   session NULL     -> transport-connected. send_to_channel PUSHES via pusher.
#
# The queue exists to cover that window, but a pending connection is created with
# `expires_at = Time.current + transport.expire_new_connection_in` (default
# **10 seconds**, connection.rb:27) and `Connection.active` calls
# `Connection.expired.delete_all` -- so the queued message is thrown away with its
# connection ~10s later and the client never sees it.
#
# A step that loads a collection proves only that the LOAD completed; the
# handshake may still be in flight, and under CI load it routinely is. Diagnosed
# on pipeline 6619, where the two failing cells created QueuedMessages and the two
# passing cells did not -- a 4/4 split.
#
# So: wait for the transport-connected state before broadcasting. Deterministic --
# it removes the race rather than widening a window.
module WaitForTransportConnection
  def wait_for_transport_connection(channel = 'TestApplication')
    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.1 until Hyperstack::Connection.exists?(channel: channel, session: nil)
    end
  rescue Timeout::Error
    raise "client never completed the pusher handshake for #{channel.inspect} " \
          "within #{Capybara.default_max_wait_time}s; " \
          "channels: #{Hyperstack::Connection.active.inspect}"
  end
end

RSpec.configure do |config|
  config.include WaitForAjax
  config.include CheckErrors
  config.include WaitForTransportConnection
end

RSpec.configure do |config|
  # rspec-expectations config goes here. You can use an alternate
  # assertion/expectation library such as wrong or the stdlib/minitest
  # assertions if you prefer.
  config.expect_with :rspec do |expectations|
    # Enable only the newer, non-monkey-patching expect syntax.
    # For more details, see:
    #   - http://myronmars.to/n/dev-blog/2012/06/rspecs-new-expectation-syntax
    expectations.syntax = [:should, :expect]
  end

  # rspec-mocks config goes here. You can use an alternate test double
  # library (such as bogus or mocha) by changing the `mock_with` option here.
  config.mock_with :rspec do |mocks|
    # Enable only the newer, non-monkey-patching expect syntax.
    # For more details, see:
    #   - http://teaisaweso.me/blog/2013/05/27/rspecs-new-message-expectation-syntax/
    mocks.syntax = :expect

    # Prevents you from mocking or stubbing a method that does not exist on
    # a real object. This is generally recommended.
    mocks.verify_partial_doubles = true
  end

  config.include FactoryBot::Syntax::Methods if defined? FactoryBot

  config.use_transactional_fixtures = false

  Capybara.default_max_wait_time = 30.seconds

  config.before(:suite) do
    #DatabaseCleaner.clean_with(:truncation)
    Hyperstack.configuration do |config|
      config.transport = :simple_poller
    end
  end

  # Reset the cleaning strategy before every example. DatabaseCleaner.strategy
  # is global state, so without this the first `js: true` example flips it to
  # :truncation (below) and every subsequent *non-js* example keeps truncating
  # needlessly. Non-js examples don't cross the test/Puma thread boundary, so a
  # fast transaction rollback is sufficient and correct for them.
  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end

  # Same process as the Capybara server, so this is true -- but state it through
  # the setting instead of redefining the predicate, which would hide #105 again.
  config.before(:each) do |x|
    Hyperstack.on_server = true
  end

  config.before(:each) do |ex|
    class ActiveRecord::Base
      regulate_scope :unscoped
    end
  end

  config.before(:each, js: true) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before(:each, :js => true) do
    size_window
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do |example|
    # I am assuming the unless was there just to aid in debug when using pry.rescue
    # perhaps it could be on a switch detecting presence of pry.rescue?
    #unless example.exception
      # Clear session data
      Capybara.reset_sessions!
      # Rollback transaction
      DatabaseCleaner.clean
    #end
  end

  config.after(:all, :js => true) do
    #size_window(:default)
  end

  config.before(:all) do
    # reset this variable so if any specs are setting up models locally
    # the correct hash gets sent to the client.
    ActiveRecord::Base.instance_variable_set('@public_columns_hash', nil)
    class ActiveRecord::Base
      class << self
        alias original_public_columns_hash public_columns_hash
      end
    end
    module Hyperstack
      def self.on_error(_operation, _err, _params, formatted_error_message)
        ::Rails.logger.debug(
          "#{formatted_error_message}\n\n" +
          Pastel.new.red(
            'To further investigate you may want to add a debugging '\
            'breakpoint to the on_error method in config/initializers/hyperstack.rb'
          )
        )
      end
    end
  end

  config.after(:all) do
    class ActiveRecord::Base
      class << self
        alias public_columns_hash original_public_columns_hash
      end
    end
  end

  config.after(:each, :js => true) do
    page.instance_variable_set("@hyper_spec_mounted", false)
  end

  # Fail tests on JavaScript errors in Chrome Headless
  class JavaScriptError < StandardError; end

  config.after(:each, js: true) do |spec|
    logs = page.driver.browser.logs.get(:browser)
    if spec.exception
      all_messages = logs.select { |e| e.message.present? }
                         .map { |m| m.message.gsub(/\\n/, "\n") }.to_a
      puts "Javascript client console messages:\n\n" +
           all_messages.join("\n\n") if all_messages.present?
    end
    errors = logs.select { |e| e.level == "SEVERE" && e.message.present? }
                .map { |m| m.message.gsub(/\\n/, "\n") }.to_a
    if client_options[:deprecation_warnings] == :on
      warnings = logs.select { |e| e.level == "WARNING" && e.message.present? }
                  .map { |m| m.message.gsub(/\\n/, "\n") }.to_a
      puts "\033[0;33;1m\nJavascript client console warnings:\n\n" + warnings.join("\n\n") + "\033[0;30;21m" if warnings.present?
    end
    if client_options[:raise_on_js_errors] == :show && errors.present?
      puts "\033[031m\nJavascript client console errors:\n\n" + errors.join("\n\n") + "\033[0;30;21m"
    elsif client_options[:raise_on_js_errors] == :debug && errors.present?
      binding.pry
    elsif client_options[:raise_on_js_errors] != :off && errors.present?
      raise JavaScriptError, errors.join("\n\n")
    end
  end

  config.include Capybara::DSL

  # Use legacy hyper-spec on_client behavior
  HyperSpec::Helpers.alias_method :on_client, :before_mount
end

FactoryBot.define do

  sequence :seq_number do |n|
    " #{n}"
  end

end if defined? FactoryBot
