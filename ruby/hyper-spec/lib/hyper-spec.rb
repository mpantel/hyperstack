# hyper-spec
# Install the Ruby 3.4 chilled-string warning filter first, before the gems that
# trigger it (unparser/parser, em-websocket, unicode_utils) are required.
require 'hyper-spec/internal/warning_filter'
require 'action_view'
require 'opal'
require 'unparser'
require 'method_source'
require 'filecache'
# require 'webdrivers'


require 'capybara/rspec'
require 'rspec/retry'
require 'hyper-spec/internal/client_execution'
require 'hyper-spec/internal/component_mount'
require 'hyper-spec/internal/controller'
require 'hyper-spec/internal/copy_locals'
require 'hyper-spec/internal/driver_timeouts'
require 'hyper-spec/internal/patches'
require 'hyper-spec/internal/rails_controller_helpers'
require 'hyper-spec/internal/time_cop.rb'
require 'hyper-spec/internal/window_sizing'

require 'hyper-spec/controller_helpers'

require 'hyper-spec/wait_for_ajax'

require 'hyper-spec/async_expectation_target'
require 'hyper-spec/helpers'
require 'hyper-spec/expectations'

require 'prism'
if defined?(Selenium::WebDriver::Firefox)
  require 'selenium/web_driver/firefox/profile'
end
# require 'selenium-webdriver'

require 'hyper-spec/version'


begin
  require 'pry'
rescue LoadError
  nil
end

module HyperSpec
  # Server-side prerendering requires mini_racer (see contextual_renderer.rb).
  # While mini_racer is disabled, prerendering is gated off so that
  # render_on: :both/:server_only mounts fall back to client-only rendering
  # instead of raising. Set HYPER_SPEC_PRERENDERING=off to disable.
  # Re-enable tracked in the "restore server-side prerendering" issue.
  def self.prerendering_disabled?
    %w[0 off no false].include?(ENV['HYPER_SPEC_PRERENDERING'].to_s.strip.downcase)
  end

  # Parses spec-authored Ruby source (e.g. a mount/evaluate_ruby block) into a
  # Parser::AST::Node tree, for Unparser to re-render as Opal-compilable code.
  # Uses Prism (bundled with Ruby since 3.3) instead of Parser::CurrentRuby,
  # which has no grammar for Ruby versions newer than 3.4 (see #35).
  def self.parse_ruby(source)
    buffer = Parser::Source::Buffer.new('(spec)')
    buffer.source = source
    Prism::Translation::Parser.new.parse(buffer)
  end
end

# opt-in to most recent AST format:
Parser::Builders::Default.emit_lambda              = true
Parser::Builders::Default.emit_procarg0            = true
(Parser::Builders::Default.emit_encoding            = true) rescue nil
(Parser::Builders::Default.emit_index               = true) rescue nil
(Parser::Builders::Default.emit_arg_inside_procarg0 = true) rescue nil
(Parser::Builders::Default.emit_forward_arg         = true) rescue nil
(Parser::Builders::Default.emit_kwargs              = true) rescue nil
(Parser::Builders::Default.emit_match_pattern       = true) rescue nil

# not available in parser 2.3
if Parser::Builders::Default.respond_to? :emit_arg_inside_procarg0
  Parser::Builders::Default.emit_arg_inside_procarg0 = true
end

# Prism::Translation::Parser::Builder subclasses Parser::Builders::Default, but
# these emit_* flags are per-class instance variables, not inherited - without
# setting them here too, HyperSpec.parse_ruby (see above) emits generic `:send`
# nodes for indexing/lambdas/pattern-matching instead of the specialized node
# types Unparser expects, breaking things like `hash['foo'] += 1` (Unparser
# emits invalid `hash.[]("foo") += 1` for the generic form).
Prism::Translation::Parser::Builder.emit_lambda              = true
Prism::Translation::Parser::Builder.emit_procarg0            = true
(Prism::Translation::Parser::Builder.emit_encoding            = true) rescue nil
(Prism::Translation::Parser::Builder.emit_index               = true) rescue nil
(Prism::Translation::Parser::Builder.emit_arg_inside_procarg0 = true) rescue nil
(Prism::Translation::Parser::Builder.emit_forward_arg         = true) rescue nil
(Prism::Translation::Parser::Builder.emit_kwargs              = true) rescue nil
(Prism::Translation::Parser::Builder.emit_match_pattern       = true) rescue nil

module HyperSpec
  if defined? Pry
    # add a before eval hook to pry so we can capture the source
    class << self
      attr_accessor :current_pry_code_block
      Pry.hooks.add_hook(:before_eval, 'hyper_spec_code_capture') do |code|
        HyperSpec.current_pry_code_block = code
      end
    end
  end

  def self.reset_between_examples
    @reset_between_examples ||= []
  end

  def self.reset_between_examples?
    RSpec.configuration.reset_between_examples
  end

  def self.reset_sessions!
    Capybara.old_reset_sessions!
  end
end

# TODO: figure out why we need this patch - its because we are on an old version
# of Selenium Webdriver, but why?
require 'selenium-webdriver'

# module Selenium
#   module WebDriver
#     module Chrome
#       module Bridge
#         if const_defined?(:COMMANDS)
#           COMMANDS = remove_const(:COMMANDS).dup
#           COMMANDS[:get_log] = [:post, 'session/:session_id/log']
#           COMMANDS.freeze
#         end
#
#         def log(type)
#           data = execute :get_log, {}, type: type.to_s
#
#           Array(data).map do |l|
#             begin
#               LogEntry.new l.fetch('level', 'UNKNOWN'), l.fetch('timestamp'), l.fetch('message')
#             rescue KeyError
#               next
#             end
#           end
#         end
#       end
#     end
#   end
# end

module Capybara
  class << self
    alias old_reset_sessions! reset_sessions!
    def reset_sessions!
      old_reset_sessions! if HyperSpec.reset_between_examples?
    end
  end
end

RSpec.configure do |config|
  config.add_setting :reset_between_examples, default: true
  config.before(:all, no_reset: true) do
    HyperSpec.reset_between_examples << RSpec.configuration.reset_between_examples
    RSpec.configuration.reset_between_examples = false
  end
  config.before(:all, no_reset: false) do
    HyperSpec.reset_between_examples << RSpec.configuration.reset_between_examples
    RSpec.configuration.reset_between_examples = true
  end
  config.after(:all) do
    HyperSpec.reset_sessions! unless HyperSpec.reset_between_examples?
    # If rspecs step is used first in a file, it will NOT call config.before(:all) causing the
    # reset_between_examples stack to be mismatched, so we check, if its already empty we
    # just leave.
    next if HyperSpec.reset_between_examples.empty?

    RSpec.configuration.reset_between_examples = HyperSpec.reset_between_examples.pop
  end
  # Put back whatever `before(:all)` (and any earlier `before(:each)`) put in the
  # mount buffers, so a retried example starts from the same state as its first
  # attempt.
  #
  # rspec-retry re-runs a failed example in the SAME example-group instance
  # (rspec_ext.rb calls `ex.run` again), so its instance variables survive the
  # attempt that failed -- and both mount buffers are CONSUMED by mounting:
  # add_block_with_helpers nils @_hyperspec_private_client_code once it has
  # compiled it into a page, and send_params_to_controller_via_cache nils
  # @_hyperspec_private_html_block. Every retry after the first therefore built
  # its page WITHOUT them, so everything the spec had put there -- `isomorphic
  # do`, `before_mount`, `insert_html`, `add_class` -- was silently gone.
  #
  # The reported failure is the last attempt's, which is why this surfaced as
  # "uninitialized constant <SomeModel>" that no amount of polling resolves,
  # with the real first-attempt failure hidden behind it. See #68.
  #
  # The mounted buffers (#71) are restored too, and for them the snapshot is always
  # empty: a retry starts on a page of its own, so what a previous attempt had put
  # on the client must not be replayed into it.
  config.before(:each) do
    if defined?(@_hyperspec_private_mount_buffers)
      @_hyperspec_private_client_code, @_hyperspec_private_html_block,
        @_hyperspec_private_mounted_client_code,
        @_hyperspec_private_mounted_html_block = @_hyperspec_private_mount_buffers
    else
      @_hyperspec_private_mount_buffers =
        [@_hyperspec_private_client_code, @_hyperspec_private_html_block,
         @_hyperspec_private_mounted_client_code,
         @_hyperspec_private_mounted_html_block]
    end
  end

  config.before(:each) do |example|
    insure_page_loaded(true) if example.metadata[:js] && !HyperSpec.reset_between_examples?
  end
end

RSpec.configure do |config|
  config.include HyperSpec::Helpers
  config.include HyperSpec::WaitForAjax
  config.include Capybara::DSL

  config.mock_with :rspec

  # How much narrower/shorter the page is than the window we ask the window
  # manager for -- browser chrome, and a debugger pane if one is open. Measured
  # once per run when unset. Height is not optional: without it the size a spec
  # asks for is unreachable on any browser with a title bar. (#79)
  config.add_setting :debugger_width, default: nil
  config.add_setting :debugger_height, default: nil

  # When the browser will not give size_window the size it asked for, warn (the
  # default) or raise HyperSpec::WindowSizeError. Suites that deliberately probe
  # the browser's limits want the warning; suites whose layout assertions depend
  # on the size they asked for may prefer to fail on the spot. (#77)
  config.add_setting :raise_on_unreachable_window_size, default: false

  config.before(:each) do
    if defined?(Hyperstack)
      Hyperstack.class_eval do
        def self.on_server?
          true
        end
      end
    end
    # for compatibility with HyperMesh
    if defined?(HyperMesh)
      HyperMesh.class_eval do
        def self.on_server?
          true
        end
      end
    end
  end

  config.before(:each, js: true) do
    size_window
  end

  config.after(:each, js: true) do
    page.instance_variable_set('@hyper_spec_mounted', false)
  end

  config.after(:each) do |example|
    unless example.exception
      PusherFake::Channel.reset if defined? PusherFake
    end
  end
end

# Capybara config
RSpec.configure do |config|
  config.before(:each) do |example|
    HyperSpec::Internal::Controller.current_example = example
    HyperSpec::Internal::Controller.description_displayed = false
  end

  config.add_setting :wait_for_initialization_time
  config.wait_for_initialization_time = 3

  # Bumped from 10: the browser data-sync specs (server push / websockets / AJAX)
  # are borderline against a 10s ceiling on loaded CI runners and time out
  # intermittently (wait_for_ajax "execution expired").
  Capybara.default_max_wait_time = 30

  # Browser specs occasionally fail on transient Selenium/AJAX errors
  # (Net::ReadTimeout, "execution expired") rather than real assertion failures.
  # Retry js-tagged examples a couple of times so flakiness doesn't redden CI;
  # a genuinely failing spec still fails after the retries.
  #
  # Three attempts multiply whatever one attempt costs, which is why they were
  # worth re-examining once #74 put a ceiling on a wedged browser. They stay:
  # bounded by HyperSpec::Internal::DriverTimeouts the worst case is three read
  # timeouts -- 4.5 minutes on the precompiled browser jobs -- instead of three
  # OS-level TCP timeouts (~42 minutes observed), and retrying is what absorbs
  # the genuinely transient failures this was added for in the first place.
  # What is deliberately NOT done is adding this class to the job-level `retry:`
  # in .gitlab-ci.yml: the fix is failing fast, not asking CI to run a dead
  # browser again.
  config.verbose_retry = true
  config.display_try_failure_messages = true
  config.default_sleep_interval = 1
  config.around(:each, :js) do |example|
    example.run_with_retry(retry: 3)
  end

  Capybara.register_driver :chrome_undocked do |app|
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('auto-open-devtools-for-tabs')
    
    # Set devtools preferences
    options.add_option('prefs', {
      'devtools.preferences' => {
        'currentDockState' => '"undocked"', # Or '"bottom"', '"right"', etc.
        'panel-selectedTab' => '"console"'
      }
    })

    # Set logging preferences
    options.add_option('goog:loggingPrefs', { browser: 'ALL' })

    Capybara::Selenium::Driver.new(
      app,
      browser: :chrome,
      capabilities: options
    )
  end

  Capybara.register_driver :chrome_docked do |app|
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('auto-open-devtools-for-tabs')
    
    # Set devtools preferences
    options.add_option('prefs', {
      'devtools.preferences' => {
        'currentDockState' => '"right"',
        'panel-selectedTab' => '"console"'
      }
    })

    # Set logging preferences
    options.add_option('goog:loggingPrefs', { browser: 'ALL' })

    Capybara::Selenium::Driver.new(
      app,
      browser: :chrome,
      capabilities: options
    )
  end

  Capybara.register_driver :chrome do |app|
    options = Selenium::WebDriver::Chrome::Options.new
    options.logging_prefs = { browser: 'ALL' } # if ENV['LOG_JS']

    Capybara::Selenium::Driver.new(
      app,
      browser: :chrome,
      options: options
    )
  end

  Capybara.register_driver :firefox do |app|
    Capybara::Selenium::Driver.new(app, browser: :firefox)
  end

  Capybara.register_driver :chrome_headless_docker_travis do |app|
    options = ::Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    Selenium::WebDriver::Chrome::Service.driver_path = '/usr/lib/chromium-browser/chromedriver'
    Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
  end

  Capybara.register_driver :firefox_headless do |app|
    options = Selenium::WebDriver::Firefox::Options.new
    options.args << '--headless'
    Capybara::Selenium::Driver.new(app, browser: :firefox, options: options)
  end if defined?(Selenium::WebDriver::Firefox)

  Capybara.register_driver :selenium_with_firebug do |app|
    profile = Selenium::WebDriver::Firefox::Profile.new
    ENV['FRAME_POSITION'] && profile.frame_position = ENV['FRAME_POSITION']
    profile.enable_firebug
    options = Selenium::WebDriver::Firefox::Options.new(profile: profile)
    Capybara::Selenium::Driver.new(app, browser: :firefox, options: options)
  end if defined?(Selenium::WebDriver::Firefox)

  Capybara.register_driver :safari do |app|
    Capybara::Selenium::Driver.new(app, browser: :safari)
  end

  Capybara.register_driver :selenium_remote do |app|
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless=new')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--window-size=1400,1400')
    options.add_option('goog:loggingPrefs', { browser: 'ALL' })
    Capybara::Selenium::Driver.new(
      app,
      browser: :remote,
      url: ENV['SELENIUM_REMOTE_URL'] || 'http://localhost:4444/wd/hub',
      options: options
    )
  end

  # Every registration above, plus the ones Capybara ships that the case below
  # can select (`:selenium_chrome_headless` is the default when DRIVER is unset),
  # gets an HTTP read timeout so a wedged browser fails in minutes rather than
  # holding the runner until a human notices. (#74)
  #
  # Capybara's own are wrapped rather than rewritten, so they keep whatever
  # browser flags a Capybara upgrade adds to them.
  HyperSpec::Internal::DriverTimeouts.bound!(::Capybara.drivers.names)

  Capybara.javascript_driver =
    case ENV['DRIVER']
    when 'remote' then :selenium_remote
    when 'beheaded' then :firefox_headless
    when 'chrome_undocked' then :chrome_undocked
    when 'chrome_docked' then :chrome_docked
    when 'chrome' then :chrome
    when 'ff' then :selenium_with_firebug
    when 'firefox' then :firefox
    when 'headless' then :selenium_chrome_headless
    when 'safari' then :safari
    when 'travis' then :chrome_headless_docker_travis
    when 'selenium_chrome' then :selenium_chrome
    else :selenium_chrome_headless
    end
end