require 'spec_helper'
require 'stringio'

# Regression coverage for #77.
#
# size_window used to be unable to fail. Two things made that so:
#
#   - wait_for_size stopped waiting as soon as EITHER dimension had held still
#     for five polls (0.25s), with tallies that never reset. A resize that the
#     browser had not applied yet looks exactly like a dimension holding still,
#     so under load the wait ended on a window that was never resized.
#   - size_window then threw the result away -- `rescue StandardError; true` --
#     so the caller was told the resize had worked.
#
# In CI that surfaced as `hyper_spec.rb:779 # will size_window to a custom size`
# asking a 480x640 window for 600x600 and asserting on a window still 480 wide.
# All three rspec-retry attempts reported 480, because each attempt re-ran the
# preceding step and hit the same 0.25s bail; retrying the job in a fresh
# container went green. Nothing anywhere said the window was the wrong size.
#
# The unit examples below drive wait_for_size against a scripted browser, so the
# sequence that failed in CI is reproduced exactly and without a real one.

# The smallest thing that can stand in for a browser being resized: each poll
# of the window size returns the next entry, and the last entry repeats for as
# long as we keep asking.
class ScriptedBrowser
  include HyperSpec::Internal::WindowSizing

  def initialize(sizes)
    @sizes = sizes
  end

  def evaluate_script(_js)
    @sizes.size > 1 ? @sizes.shift : @sizes.first
  end

  def wait_for(width, height)
    send(:wait_for_size, width, height)
  end

  def report(requested, achieved, outcome)
    send(:report_window_size, requested, achieved, outcome)
  end

  def size_for(width, height)
    send(:determine_size, width, height)
  end
end

describe 'size_window' do
  before do
    HyperSpec::Internal::WindowSizing::REPORTED_SIZES.clear
    HyperSpec::Internal::WindowSizing::KNOWN_LIMITS.clear
  end

  describe 'waiting for the browser' do
    it 'keeps waiting while a resize it asked for has not been applied yet' do
      # Eight polls of an unchanged 480x640 -- comfortably past the five that
      # used to end the wait -- and only then does the resize land.
      browser = ScriptedBrowser.new([[480, 640]] * 8 + [[600, 600]])

      expect(browser.wait_for(600, 600)).to eq([[600, 600], :reached])
    end

    it 'keeps waiting when only one dimension has arrived' do
      # The shape of the CI failure: the height is there, the width is not.
      browser = ScriptedBrowser.new([[480, 600]] * 8 + [[600, 600]])

      expect(browser.wait_for(600, 600)).to eq([[600, 600], :reached])
    end

    it 'gives up on a size the browser holds against, and says what it got' do
      browser = ScriptedBrowser.new([[480, 600]])

      expect(browser.wait_for(600, 600)).to eq([[480, 600], :stalled])
    end

    it 'returns as soon as the size is reached' do
      browser = ScriptedBrowser.new([[600, 600]])

      expect(browser.wait_for(600, 600)).to eq([[600, 600], :reached])
    end

    it 'does not pay the full grace period for a limit it has already proved' do
      # Otherwise a suite whose before hook asks for a size this browser cannot
      # give would pay that grace period once per example.
      ScriptedBrowser.new([[480, 600]]).wait_for(600, 600)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      ScriptedBrowser.new([[480, 600]]).wait_for(600, 600)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(elapsed).to be < HyperSpec::Internal::WindowSizing::STABLE_TIME
    end
  end

  describe 'reporting a size the browser will not give' do
    let(:browser) { ScriptedBrowser.new([[480, 600]]) }

    # these examples warn on purpose -- keep it out of the suite's own output
    def quietly
      original = $stderr
      $stderr = StringIO.new
      yield
    ensure
      $stderr = original
    end

    it 'warns, naming what was asked for and what was got' do
      expect { browser.report([600, 600], [480, 600], :stalled) }
        .to output(/could not size the window to 600x600.*settled at 480x600/m).to_stderr
    end

    it 'warns once per distinct discrepancy' do
      # The js before hook sizes the window for every example; a suite in a
      # window the browser clamps must not repeat one line thousands of times.
      quietly { browser.report([600, 600], [480, 600], :stalled) }

      expect { browser.report([600, 600], [480, 600], :stalled) }
        .not_to output.to_stderr
    end

    it 'returns the size the browser actually settled on' do
      expect(quietly { browser.report([600, 600], [480, 600], :stalled) }).to eq([480, 600])
    end

    it 'raises instead when the suite has asked it to' do
      RSpec.configuration.raise_on_unreachable_window_size = true

      expect { browser.report([600, 600], [480, 600], :stalled) }
        .to raise_error(HyperSpec::WindowSizeError, /600x600.*480x600/m)
    ensure
      RSpec.configuration.raise_on_unreachable_window_size = false
    end
  end

  # A window manager plus a browser with chrome: resize_to sets the OUTER size,
  # the page gets that minus the chrome. Records what it was asked for so the
  # examples can assert the correction was applied on the way out.
  class ChromedBrowser
    include HyperSpec::Internal::WindowSizing

    CHROME = [12, 143].freeze

    attr_reader :asked_for

    def initialize(min_outer_height: 0)
      @min_outer_height = min_outer_height
      @outer = [1024, 768]
    end

    # stands in for Capybara.current_session.current_window
    def resize_to(width, height)
      @asked_for = [width, height]
      @outer = [width, [height, @min_outer_height].max]
    end

    def inner = [@outer[0] - CHROME[0], @outer[1] - CHROME[1]]

    def evaluate_script(js)
      js.include?('outerWidth') ? [*@outer, *inner] : inner
    end

    def resize(width, height) = send(:hs_internal_resize_to, width, height)
    def chrome = send(:window_chrome)
  end

  describe 'correcting for window chrome' do
    let(:browser) { ChromedBrowser.new }

    # the chrome is measured once and cached on the configuration, so each
    # example has to start from unmeasured
    before do
      @original = [RSpec.configuration.debugger_width, RSpec.configuration.debugger_height]
      RSpec.configuration.debugger_width = nil
      RSpec.configuration.debugger_height = nil
      drive(browser)
    end

    after do
      RSpec.configuration.debugger_width, RSpec.configuration.debugger_height = @original
    end

    def drive(window)
      allow(Capybara).to receive(:current_session).and_return(
        Struct.new(:current_window, :config).new(
          window, Struct.new(:default_max_wait_time).new(5)
        )
      )
    end

    it 'measures both axes, not just width' do
      expect(browser.chrome).to eq(ChromedBrowser::CHROME)
    end

    it 'reaches the inner size that was asked for' do
      # Before #79 only width was corrected, so innerHeight came back 143 short
      # of the request, `:reached` was unreachable, and every resize fell through
      # to the "browser will not go further" branch -- which accepts whatever the
      # window happens to be, including a resize that has not landed yet.
      achieved, outcome = browser.resize(1024, 768)

      expect(outcome).to eq(:reached)
      expect(achieved).to eq([1024, 768])
    end

    it 'asks the window manager for the size plus the chrome' do
      browser.resize(1024, 768)

      expect(browser.asked_for).to eq([1024 + 12, 768 + 143])
    end

    it 'still reports a size the browser genuinely refuses' do
      # the correction must not paper over a real limit -- that is what the
      # reporting added in #77 is for
      short = ChromedBrowser.new(min_outer_height: 700)
      drive(short)

      achieved, outcome = short.resize(480, 320)

      # width is satisfied (480 asked -> 492 outer -> 480 inner); only the height
      # runs into the window manager's floor, and that is what gets reported
      expect(outcome).to eq(:stalled)
      expect(achieved).to eq([480, 557])
    end

    it 'measures the chrome even when the probe size is refused' do
      # outer-minus-inner, not asked-for-minus-inner: a window manager with a
      # minimum height would otherwise have us measure the clamp as chrome and
      # bake that error into every later resize.
      short = ChromedBrowser.new(min_outer_height: 700)
      drive(short)

      expect(short.chrome).to eq(ChromedBrowser::CHROME)
    end
  end

  describe 'a size name it does not know' do
    # `size_window(:medium)` reached `:medium + debugger_width`, and the blanket
    # rescue turned that NoMethodError into a resize that quietly did nothing.
    # hyper-model had such a call sitting in a before hook for years.
    it 'says so, naming the sizes it does know' do
      expect { ScriptedBrowser.new([[0, 0]]).size_for(:medium, nil) }
        .to raise_error(ArgumentError, /size_window\(:medium\).*:small.*:default/m)
    end

    it 'still resolves the names it does know' do
      original = RSpec.configuration.debugger_width
      RSpec.configuration.debugger_width = 0

      expect(ScriptedBrowser.new([[0, 0]]).size_for(:mobile, :portrait)).to eq([480, 640])
    ensure
      RSpec.configuration.debugger_width = original
    end
  end

  describe 'in a browser', js: true do
    before { calculate_window_restrictions }

    it 'returns the size the window ends up at' do
      expect(size_window(:mobile)).to eq(dims)
    end

    it 'reaches a custom size asked for from a narrower window' do
      # The CI failure, end to end: 600 wide, asked for from the 480x640 that
      # the preceding step in hyper_spec.rb leaves behind.
      skip 'this browser will not be 600 wide' unless can_be_600_wide?

      size_window(:mobile, :portrait)
      size_window(600, 600)

      expect(width).to eq(600)
    end

    # Whether the browser can be 600 wide at all is established without going
    # through the code under test -- resize it, wait longer than any resize
    # could take, look -- so that a browser which genuinely cannot skips, and a
    # browser which can cannot skip its way out of the assertion.
    #
    # @min_width is no good for this: a Chrome that refuses a below-minimum
    # resize leaves the window where it was, so the 100x100 probe in
    # calculate_window_restrictions reports the previous size as the minimum.
    def can_be_600_wide?
      Capybara.current_session.current_window.resize_to(600, 600)
      sleep 2
      width == 600
    end
  end
end
