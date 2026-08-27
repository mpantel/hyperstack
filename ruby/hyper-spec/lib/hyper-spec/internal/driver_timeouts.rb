# frozen_string_literal: true

module HyperSpec
  module Internal
    # A ceiling on how long a single WebDriver command may hang. (#74)
    #
    # Capybara's `default_max_wait_time` does NOT bound this: it is the window in
    # which Capybara *re-runs* a finder or matcher, and a retry only happens once
    # the previous command has returned. A command that never returns -- a wedged
    # browser that has stopped answering its debugging port -- is not covered by
    # it at all. With no `http_client:` on a driver registration, Selenium builds
    # a client with whatever default that version happens to carry: up to 4.46,
    # none at all, so the socket simply waits.
    #
    # Observed cost of that (pipeline 6646, hyper-operation:part2): three
    # `Net::ReadTimeout`s of ~14 minutes each -- the OS-level TCP timeout, the
    # only ceiling left -- multiplied by rspec-retry's three attempts per :js
    # example. The job held a runner for 42 minutes and was cancelled by hand;
    # the re-run passed in 95 seconds.
    #
    # A read timeout turns that into a fast, legible failure. It has to clear the
    # slowest command a *healthy* run can legitimately issue, which is not an
    # assertion -- those are bounded by `default_max_wait_time` -- but `visit`:
    # chromedriver does not answer the navigate command until the page has
    # loaded, so whatever the page costs to serve is charged to a single HTTP
    # read.
    #
    # That cost is not the same in every suite, which is why the default is not
    # one number. A suite whose Opal bundle is precompiled serves it statically
    # (`assets.compile = false`) and no request has any business taking a minute
    # and a half. A suite still on the debug pipeline compiles Sprockets assets
    # per request, and the first visit of the run pays a cold compile of the
    # whole bundle inside that one navigate -- the readme's "the first spec
    # appears to hang for minutes". The same flag the test_apps already switch
    # `assets.compile` on tells us which of the two we are in, so each gets a
    # ceiling that only a wedged browser can hit.
    module DriverTimeouts
      # Seconds. Override either of them with HYPER_SPEC_READ_TIMEOUT /
      # HYPER_SPEC_OPEN_TIMEOUT. Setting one to 0 means "impose nothing", which
      # leaves the installed selenium-webdriver's own default -- and that is
      # version-dependent, so 0 is not a way to ask for an unbounded wait: up to
      # 4.46 `Http::Default` sets no timeouts at all, while 4.47 introduced a
      # ClientConfig defaulting to open 60 / read 120. To sit on a breakpoint,
      # name a large number (HYPER_SPEC_READ_TIMEOUT=86400) rather than 0; that
      # reads the same on every version.
      #
      # 4.47's 120s default is itself below the cold compile below, which is
      # another reason not to leave the value to the gem.
      #
      # PRECOMPILED_ASSETS covers the browser jobs this was raised from
      # (hyper-model, hyper-operation part1/part2) and every local run through
      # run-local-docker-specs.sh.
      PRECOMPILED_READ_TIMEOUT = 90
      COLD_COMPILE_READ_TIMEOUT = 300
      DEFAULT_OPEN_TIMEOUT = 30

      class << self
        def read_timeout
          @read_timeout ||= timeout_from_env('HYPER_SPEC_READ_TIMEOUT', default_read_timeout)
        end

        # Presence, not value -- the same test the test_app configs use to decide
        # whether the bundle is served statically.
        def precompiled_assets?
          !ENV['PRECOMPILED_ASSETS'].nil?
        end

        def default_read_timeout
          precompiled_assets? ? PRECOMPILED_READ_TIMEOUT : COLD_COMPILE_READ_TIMEOUT
        end

        def open_timeout
          @open_timeout ||= timeout_from_env('HYPER_SPEC_OPEN_TIMEOUT', DEFAULT_OPEN_TIMEOUT)
        end

        # Reset the memoized values -- for specs that exercise the env parsing.
        def reset!
          @read_timeout = @open_timeout = nil
        end

        # A fresh HTTP client per call: a client owns its connection and its
        # server_url, so it can never be shared between two drivers.
        #
        # Capybara's own client is preferred when present -- it keeps the
        # connection to chromedriver alive between commands, and dropping that to
        # bolt on a timeout would trade an occasional 42-minute job for a
        # slightly slower every-command path. It is a plain subclass of
        # Selenium's default client, so it takes the same timeouts.
        def http_client
          return nil unless bounded?

          # nil leaves that timeout unset, which is what 0 asks for.
          client_class.new(
            open_timeout: open_timeout.positive? ? open_timeout : nil,
            read_timeout: read_timeout.positive? ? read_timeout : nil
          )
        end

        # Bound a driver Capybara has already built. `Capybara::Selenium::Driver`
        # does not open the browser in its constructor -- it builds the client
        # lazily, on first use, from `options[:http_client]` -- so filling that in
        # afterwards is enough, and it leaves an explicitly supplied client alone.
        #
        # Working on the built driver rather than on the arguments is what lets
        # Capybara's own registrations be wrapped without copying their bodies,
        # so they keep whatever browser flags a Capybara upgrade adds to them.
        def apply(driver)
          return driver unless bounded? && selenium_driver?(driver)

          options = driver.options
          return driver unless options.is_a?(Hash) && options[:http_client].nil?

          options[:http_client] = http_client
          driver
        end

        # Re-register `names` so each one yields a bounded driver, calling
        # through to the registration that is there now.
        def bound!(*names)
          names.flatten.each do |name|
            registration = ::Capybara.drivers[name]
            next unless registration

            ::Capybara.register_driver(name) { |app| apply(registration.call(app)) }
          end
        end

        private

        # `:rack_test` and anything else non-Selenium has no HTTP client to bound.
        def selenium_driver?(driver)
          defined?(::Capybara::Selenium::Driver) &&
            driver.is_a?(::Capybara::Selenium::Driver) &&
            driver.respond_to?(:options)
        end

        def bounded?
          read_timeout.positive? || open_timeout.positive?
        end

        def client_class
          @client_class ||=
            begin
              require 'capybara/selenium/patches/persistent_client'
              ::Capybara::Selenium::PersistentClient
            rescue LoadError, NameError
              ::Selenium::WebDriver::Remote::Http::Default
            end
        end

        # An unparseable or negative value is a typo, not a request for an
        # unbounded run -- 0 is how you ask for that, explicitly.
        def timeout_from_env(name, default)
          raw = ENV[name].to_s.strip
          return default if raw.empty?

          value = Integer(raw, exception: false)
          if value.nil? || value.negative?
            warn "hyper-spec: ignoring #{name}=#{raw.inspect} (expected a non-negative integer), using #{default}"
            return default
          end

          value
        end
      end
    end
  end
end
