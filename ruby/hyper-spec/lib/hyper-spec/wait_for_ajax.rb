module HyperSpec
  module WaitForAjax
    # How long to wait between "is anything running?" polls.
    AJAX_POLL_INTERVAL = 0.25
    # How many *consecutive* idle polls must be seen before declaring done.
    #
    # One idle observation is not enough: a request that starts later than a
    # single poll interval after the action that triggered it -- queued behind a
    # debounce, a requestAnimationFrame, or a Hyperstack `mutate` that
    # re-renders before dispatching the operation -- has not begun yet when that
    # first check runs. Callers that then read state directly (straight from the
    # DB, with no page-content assertion to catch a late update) get a false
    # "done" and observe pre-request state. Requiring the idle state to hold
    # across two consecutive checks gives such a late starter a poll interval to
    # show up in. (#41)
    REQUIRED_IDLE_POLLS = 2

    # Every `mount` waits here (internal/component_mount.rb), and a transport
    # that polls -- or any page still talking to the server -- can keep the
    # "running" answer coming back indefinitely. So the extra confirmation poll
    # must never turn a call that used to return into one that raises, or into
    # one that outlives the wait budget:
    #
    #   * Once the budget is spent we stop rather than start another poll.
    #     `running?` swallows *every* exception, including the Timeout::Error
    #     raised by the enclosing Timeout.timeout -- and Ruby's Timeout only
    #     fires once. A confirmation poll after that swallow would run with no
    #     timeout left at all, against a page that just proved it does not
    #     answer.
    #
    #   * If the budget runs out having seen idle at least once, we return
    #     instead of raising. Breaking on the first idle observation is exactly
    #     what this helper did before #41. Waiting longer for a confirmation is
    #     an improvement; failing the example because the confirmation never
    #     came would be a regression.
    def wait_for_ajax
      budget = Capybara.default_max_wait_time
      deadline = monotonic_now + budget
      seen_idle = false
      idle_polls = 0

      begin
        Timeout.timeout(budget) do
          loop do
            sleep AJAX_POLL_INTERVAL
            if finished_all_ajax_requests?
              seen_idle = true
              idle_polls += 1
              break if idle_polls >= REQUIRED_IDLE_POLLS
              break if monotonic_now >= deadline
            else
              idle_polls = 0
            end
          end
        end
      rescue Timeout::Error
        raise unless seen_idle
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
              return (jQuery.active > 0);
            } else {
              return false;
            }
          }
        } else if (typeof jQuery !== "undefined" && jQuery.active !== undefined) {
          return (jQuery.active > 0);
        } else {
          return false;
        }
      })();
      CODE
      Capybara.page.evaluate_script(jscode)
    rescue Exception => e
      puts "wait_for_ajax failed while testing state of ajax requests: #{e}"
    end

    def finished_all_ajax_requests?
      !running?
    rescue Capybara::NotSupportedByDriverError
      true
    rescue Exception => e
      e.message == 'either jQuery or Hyperstack::HTTP is not defined'
    end

    private

    # Wall-clock changes (Timecop, and Lolex's client clock) must not move this
    # deadline.
    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
