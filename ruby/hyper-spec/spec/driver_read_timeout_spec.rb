require 'spec_helper'
require 'capybara/selenium/patches/persistent_client'

# Regression coverage for #74.
#
# A driver registered without an `http_client:` gets Selenium's default one,
# which sets no read timeout: when the browser stops answering, the socket waits
# until the OS gives up (~14 minutes observed). Capybara's `default_max_wait_time`
# does not help -- it bounds how long Capybara keeps *re-trying* a finder, and a
# retry only comes after the previous command returns. rspec-retry then pays that
# cost three times per :js example, which is how one wedged Chrome held a CI
# runner for 42 minutes before a human cancelled it.
#
# So the property under test is per-registration and structural: build the driver
# (Capybara builds it without launching a browser -- the client is made lazily on
# first use) and look at the client it would use.
describe 'the read timeout on every registered driver' do
  # A method rather than a local, so the helpers defined with `def` below can
  # reach it too.
  def timeouts
    HyperSpec::Internal::DriverTimeouts
  end

  # Every driver `Capybara.javascript_driver` can be set to from DRIVER, plus
  # rack_test, which has no HTTP client at all and must be left alone.
  #
  # :selenium_with_firebug is deliberately absent: building it calls
  # `profile.enable_firebug`, which no current selenium-webdriver provides, so it
  # raises before a client is ever involved. It has no timeout to assert.
  selectable = %i[
    selenium_remote firefox_headless chrome_undocked chrome_docked chrome
    firefox selenium_chrome_headless safari chrome_headless_docker_travis
    selenium_chrome
  ]

  def build(name)
    registration = Capybara.drivers[name]
    raise "no driver registered as #{name.inspect}" unless registration

    registration.call(Object.new)
  end

  def client_for(driver)
    # Same lookup Capybara::Selenium::Driver#browser does on first use.
    driver.options[:http_client]
  end

  # What a driver would get if hyper-spec registered no client at all.
  def bare_client
    Selenium::WebDriver::Remote::Http::Default.new
  end

  around do |example|
    # :chrome_headless_docker_travis pins the chromedriver path as a side effect
    # of being built, which would otherwise leak into the browser specs that run
    # after this file in the same process.
    saved = Selenium::WebDriver::Chrome::Service.driver_path
    example.run
    Selenium::WebDriver::Chrome::Service.driver_path = saved
  end

  selectable.each do |name|
    it "bounds :#{name}" do
      skip "#{name} is not registered in this environment" unless Capybara.drivers[name]

      driver =
        begin
          build(name)
        rescue Selenium::WebDriver::Error::WebDriverError => e
          # :chrome_headless_docker_travis pins a chromedriver path that exists
          # only in the CI image; off CI it cannot be built at all.
          skip "#{name} cannot be built in this environment: #{e.message}"
        end

      client = client_for(driver)
      expect(client).not_to be_nil,
                            "#{name} would use Selenium's default client, which never times out"
      expect(client.read_timeout).to eq(timeouts.read_timeout)
      expect(client.open_timeout).to eq(timeouts.open_timeout)
    end
  end

  it 'leaves :rack_test alone, which speaks no HTTP to a browser' do
    expect { build(:rack_test) }.not_to raise_error
  end

  it 'keeps the connection to the browser alive' do
    # Bolting a timeout on by handing Selenium a plain client would silently drop
    # Capybara's persistent one and reconnect on every single command.
    expect(client_for(build(:chrome))).to be_a(Capybara::Selenium::PersistentClient)
  end

  it 'defaults comfortably above default_max_wait_time' do
    # A read timeout at or below the assertion window would pre-empt legitimately
    # slow waits instead of only catching wedged browsers.
    expect(timeouts.read_timeout).to be > Capybara.default_max_wait_time
  end

  it 'does not override a driver that supplies its own client' do
    own = Selenium::WebDriver::Remote::Http::Default.new(read_timeout: 7)
    driver = Capybara::Selenium::Driver.new(Object.new, browser: :chrome, http_client: own)

    expect(client_for(timeouts.apply(driver))).to be(own)
  end

  describe 'configuration' do
    keys = %w[HYPER_SPEC_READ_TIMEOUT HYPER_SPEC_OPEN_TIMEOUT PRECOMPILED_ASSETS]

    around do |example|
      saved = ENV.values_at(*keys)
      example.run
      keys.each_with_index { |key, i| ENV[key] = saved[i] }
      timeouts.reset!
    end

    def with_env(read: nil, open: nil, precompiled: nil)
      ENV['HYPER_SPEC_READ_TIMEOUT'] = read
      ENV['HYPER_SPEC_OPEN_TIMEOUT'] = open
      ENV['PRECOMPILED_ASSETS'] = precompiled
      timeouts.reset!
      yield
    end

    # The ceiling has to clear the slowest thing a healthy run does, and that is
    # not the same in both asset modes: a precompiled bundle is served
    # statically, while the debug pipeline charges a cold Sprockets compile of
    # the whole bundle to the first `visit`'s navigate command.
    it 'is tight when the bundle is precompiled' do
      with_env(precompiled: '1') do
        expect(timeouts.read_timeout).to eq(timeouts::PRECOMPILED_READ_TIMEOUT)
      end
    end

    it 'leaves room for the cold compile when it is not' do
      with_env(precompiled: nil) do
        expect(timeouts.read_timeout).to eq(timeouts::COLD_COMPILE_READ_TIMEOUT)
      end
    end

    it 'still bounds the cold-compile case well below the ~14 minutes it replaces' do
      expect(timeouts::COLD_COMPILE_READ_TIMEOUT).to be < 600
      expect(timeouts::PRECOMPILED_READ_TIMEOUT).to be > Capybara.default_max_wait_time
    end

    it 'takes the timeouts from the environment' do
      with_env(read: '45', open: '5') do
        expect(timeouts.read_timeout).to eq(45)
        expect(timeouts.open_timeout).to eq(5)
      end
    end

    it 'restores the unbounded behaviour at 0, for debugger sessions' do
      with_env(read: '0', open: '0') do
        expect(timeouts.http_client).to be_nil
      end
    end

    it 'sets only the timeout that is asked for' do
      with_env(read: '45', open: '0') do
        client = timeouts.http_client
        expect(client.read_timeout).to eq(45)
        # 0 means "impose nothing", so what is left is whatever the installed
        # selenium-webdriver defaults to -- and that is not one answer: <= 4.46
        # sets no timeouts at all, 4.47's ClientConfig defaults to 60/120. Ask a
        # bare client rather than hard-coding either version's number.
        expect(client.open_timeout).to eq(bare_client.open_timeout)
      end
    end

    it "replaces selenium's own default rather than inheriting it" do
      # The whole point of #74: on 4.46 and older a bare client has no read
      # timeout at all, and 4.47's 120s default is itself too tight for the
      # debug-pipeline cold compile. Either way the value in force has to be
      # ours.
      with_env(read: '45') do
        expect(timeouts.http_client.read_timeout).to eq(45)
        expect(bare_client.read_timeout).not_to eq(45)
      end
    end

    it 'falls back to the default rather than trusting a typo' do
      with_env(read: 'ninety') do
        expect { timeouts.read_timeout }.to output(/HYPER_SPEC_READ_TIMEOUT/).to_stderr
        expect(timeouts.read_timeout).to eq(timeouts.default_read_timeout)
      end
    end
  end
end
