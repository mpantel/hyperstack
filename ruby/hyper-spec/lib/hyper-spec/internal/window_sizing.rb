module HyperSpec
  # Raised by size_window when the browser will not give us the size we asked
  # for, and the suite has set
  #   RSpec.configuration.raise_on_unreachable_window_size = true
  # Off by default: a suite that deliberately probes the browser's limits (ask
  # for 100x100, see what you get) is doing something legitimate. (#77)
  class WindowSizeError < StandardError; end

  module Internal
    module WindowSizing
      # Each distinct "asked for X, got Y" is reported once per run. The js
      # before hook calls size_window for EVERY example, so a suite running in
      # a window the browser clamps would otherwise repeat one line thousands
      # of times and bury everything else. (#77)
      REPORTED_SIZES = {}

      private

      STD_SIZES = {
        small: [480, 320],
        mobile: [640, 480],
        tablet: [960, 640],
        large: [1920, 6000],
        default: [1024, 768]
      }

      def determine_size(width, height)
        requested = [width, height]
        width, height = [height, width] if width == :portrait
        width, height = width if width.is_a? Array
        portrait = true if height == :portrait
        width ||= :default
        width, height = STD_SIZES[width] if STD_SIZES[width]
        check_size!(width, height, requested)
        width, height = [height, width] if portrait
        # The INNER size the caller asked for. The correction for window chrome
        # is applied at the point of the resize, not here, so that what we wait
        # for and what the caller asked for are the same numbers. (#79)
        [width, height]
      end

      # A name that is not one of STD_SIZES fell through to `symbol + debugger_width`
      # and raised NoMethodError, which size_window's blanket rescue then swallowed:
      # `size_window(:medium)` sized nothing at all, silently, for years. Say what
      # was wrong with it instead. (#77)
      def check_size!(width, height, requested)
        return if width.is_a?(Numeric) && height.is_a?(Numeric)

        raise ArgumentError,
              "size_window(#{requested.compact.map(&:inspect).join(', ')}) is not a size "\
              "hyper-spec knows: pass a width and a height, or one of "\
              "#{STD_SIZES.keys.map(&:inspect).join(', ')}."
      end

      # The gap between the size the window manager is asked for and the size the
      # page actually gets. `resize_to` sets the OUTER window; every assertion in
      # the suite is about `window.innerWidth`/`innerHeight`. Browser chrome,
      # toolbars and an open debugger pane all live in that difference.
      #
      # Width had a correction for this and height had none, so on any browser
      # with chrome the height comparison could never be satisfied: ask for 768,
      # innerHeight comes back 625, and wait_for_size falls through to its "the
      # browser will not go further" branch on EVERY resize -- accepting whatever
      # size the window happened to be at, including one a resize had not landed
      # on yet. That is what made `will size_window to` fail under load, and why
      # every CI run printed a "could not size the window" line for sizes the
      # browser had no objection to. (#79)
      #
      # Both halves stay settable: a suite that knows its own chrome can set
      # either and skip the probe.
      def window_chrome
        config = RSpec.configuration
        unless config.debugger_width && config.debugger_height
          measured = measure_window_chrome
          config.debugger_width  ||= measured[0]
          config.debugger_height ||= measured[1]
        end
        [config.debugger_width, config.debugger_height]
      end

      # Deliberately NOT routed through hs_internal_resize_to: that asks
      # window_chrome for the correction, and this is where the correction comes
      # from. It also must not wait for a size to be "reached" -- reaching one is
      # precisely what it is here to make possible.
      #
      # Measured as outer MINUS inner rather than "what we asked for" minus inner,
      # so it does not matter whether the probe size was honoured: a window
      # manager with a minimum height would otherwise have us measure the clamp
      # instead of the chrome, and bake that error into every later resize.
      def measure_window_chrome
        Capybara.current_session.current_window.resize_to(1000, 500)
        sleep RSpec.configuration.wait_for_initialization_time
        # one round trip, so the two sizes cannot be read a resize apart
        outer_w, outer_h, inner_w, inner_h = evaluate_script(
          '[window.outerWidth, window.outerHeight, window.innerWidth, window.innerHeight]'
        )
        [outer_w - inner_w, outer_h - inner_h]
      end

      # Kept for anything reading the width correction by its old name.
      def debugger_width
        window_chrome[0]
      end

      # Returns [[width, height], outcome] where outcome is one of :reached,
      # :stalled or :timed_out -- see wait_for_size.
      #
      # `width`/`height` are the INNER size wanted; the chrome correction is
      # added on the way out to the window manager and never leaks into what we
      # compare against, so `:stalled` now means the browser genuinely refused,
      # rather than "there is a title bar". (#79)
      def hs_internal_resize_to(width, height)
        chrome_width, chrome_height = window_chrome
        Capybara.current_session.current_window
                .resize_to(width + chrome_width, height + chrome_height)
        yield if block_given?
        wait_for_size(width, height)
      end

      # How long the window has to hold one size before we accept that the
      # browser is not going to give us the size we asked for.
      #
      # The old test was five polls -- 0.25s -- of EITHER dimension holding
      # still, counted with tallies that never reset. A browser under load trips
      # over that routinely: the CI failure this comes from asked a 480x640
      # window for 600x600, and a quarter second of a steady width, with the
      # resize simply not applied yet, ended the wait at 480 wide. The example
      # then failed on a dimension it had asked to be 600.
      #
      # This is a grace period, not a delay. A resize that lands is returned the
      # moment it lands; only a size the browser will not honor pays the second.
      # It has to stay well under default_max_wait_time (30s in hyper-spec.rb),
      # which every js example would otherwise pay whenever a size is out of
      # reach -- a headed browser, whose window chrome means the inner size
      # never equals the outer size we set, reaches this path every time. (#77)
      STABLE_TIME = 1.0

      # A size this browser has already refused, and the size it gave instead.
      # Proving the limit costs the grace period above; being reminded of it
      # does not need to. hyper-model and friends call size_window from a
      # before hook that runs for EVERY js example, so without this a suite
      # asking for a size its browser cannot give would pay the grace period
      # thousands of times over. (#77)
      KNOWN_LIMITS = {}
      SETTLED_TIME = 0.25

      # Poll until the window is the size we asked for, or until it is clear we
      # are not going to get it. Says which of the two happened rather than
      # returning a bare true, because "the browser settled somewhere else" is
      # something the caller has to be able to act on. (#77)
      def wait_for_size(width, height)
        @start_time = Capybara::Helpers.monotonic_time
        settled_at = @start_time
        prev_size = nil
        loop do
          sleep 0.05
          curr_size = evaluate_script('[window.innerWidth, window.innerHeight]')
          now = Capybara::Helpers.monotonic_time

          return [curr_size, :reached] if curr_size == [width, height]

          # any movement at all means the browser is still working on it
          settled_at = now if curr_size != prev_size
          prev_size = curr_size

          if now - settled_at >= grace_for([width, height], curr_size)
            KNOWN_LIMITS[[width, height]] = curr_size
            return [curr_size, :stalled]
          end
          return [curr_size, :timed_out] if now - @start_time > max_wait_time
        end
      end

      # Settling exactly where this browser settled the last time it was asked
      # for this size is the limit we already know about, not a resize still on
      # its way.
      def grace_for(requested, curr_size)
        KNOWN_LIMITS[requested] == curr_size ? SETTLED_TIME : STABLE_TIME
      end

      def max_wait_time
        Capybara.current_session.config.default_max_wait_time
      end

      # Say so when the window is not the size that was asked for: a warning by
      # default, an exception when the suite has asked for one. (#77)
      def report_window_size(requested, achieved, outcome)
        message = "hyper-spec: size_window could not size the window to "\
                  "#{requested[0]}x#{requested[1]} -- #{explain(achieved, outcome)}."

        raise WindowSizeError, message if RSpec.configuration.raise_on_unreachable_window_size

        warn message unless REPORTED_SIZES.key?([requested, achieved, outcome])
        REPORTED_SIZES[[requested, achieved, outcome]] = true
        achieved
      end

      def explain(achieved, outcome)
        settled = "the browser settled at #{achieved[0]}x#{achieved[1]}"
        return "#{settled} and would go no further" if outcome == :stalled

        "#{settled} was still not the requested size after #{max_wait_time} seconds"
      end
    end
  end
end
