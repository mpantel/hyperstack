module HyperSpec
  # Waiting expectation target for `expect_evaluate_ruby` / `expect_promise`.
  #
  # Those are literally `expect(evaluate_ruby(...))`: one read, one match, no
  # retry. So they race whatever produces the value -- the same defect fixed for
  # `on_client_to` in !81/!86, on the other of the two paths.
  #
  # Not hypothetical: batch6/server_method_spec.rb:71 passed on every cell at
  # 07:42 and failed on three different cells across two unrelated MRs an hour
  # later, after ru-vm2 was reconfigured. The spec did not change; the timing did.
  #
  # ---------------------------------------------------------------------------
  # THE HAZARD, and why polling here is narrower than for on_client_to
  #
  # Polling re-evaluates the block, and `evaluate_ruby` runs the whole thing --
  # side effects included. A survey of the 475 call sites found ~19 whose blocks
  # create/update/destroy/save. For those, a first read that mismatches would
  # re-run the mutation.
  #
  # That is worse than being slow: a spec that ought to fail could pass on a
  # later attempt having duplicated records, i.e. pass for the wrong reason.
  #
  # So this deliberately differs from the on_client_to fix:
  #
  #   * the interval is 0.25s, not 0.1s -- an order fewer re-runs across the
  #     same window (roughly 120 attempts rather than 300);
  #   * only POSITIVE expectations poll. `not_to` reads once, because retrying
  #     until something stops being true is a different assertion.
  #
  # It does not remove the hazard, and pretending otherwise would be worse than
  # documenting it: a mutating block whose first read mismatches WILL re-run.
  # The 19 sites are worth reviewing if any of them starts behaving oddly.
  class AsyncExpectationTarget
    INTERVAL = 0.25

    def initialize(&producer)
      @producer = producer
    end

    def to(matcher = nil, message = nil, &block)
      target_for(settled(matcher)).to(matcher, message, &block)
    end

    # Single read: see the note above on negative expectations.
    def not_to(matcher = nil, message = nil, &block)
      target_for(@producer.call).not_to(matcher, message, &block)
    end
    alias to_not not_to

    # Anything else behaves exactly as `expect(value)` did before.
    def method_missing(name, *args, &block)
      target_for(@producer.call).public_send(name, *args, &block)
    end

    def respond_to_missing?(name, include_private = false)
      target_for(nil).respond_to?(name, include_private) || super
    end

    private

    def target_for(value)
      ::RSpec::Expectations::ExpectationTarget.for(value, nil)
    end

    def settled(matcher)
      value, error = fetch
      return raise_or(value, error) unless pollable?(matcher)

      deadline = now + ::Capybara.default_max_wait_time
      until (error.nil? && matched?(matcher, value)) || now >= deadline
        sleep INTERVAL
        value, error = fetch
      end
      raise_or(value, error)
    end

    def raise_or(value, error)
      raise error if error

      value
    end

    def fetch
      [@producer.call, nil]
    rescue ::StandardError => e
      # Only a JS error plausibly means "the client is not ready yet". Retrying
      # every StandardError would swallow real problems and make each one cost
      # the full timeout before failing.
      raise unless e.class.name.to_s.include?('Selenium::WebDriver::Error::JavascriptError')

      [nil, e]
    end

    def pollable?(matcher)
      matcher.respond_to?(:matches?) &&
        !(matcher.respond_to?(:supports_block_expectations?) &&
          matcher.supports_block_expectations?)
    end

    def matched?(matcher, value)
      matcher.matches?(value)
    rescue ::StandardError
      false
    end

    def now
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    end
  end
end
