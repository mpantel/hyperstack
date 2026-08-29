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
  #
  # ---------------------------------------------------------------------------
  # THE WORST SHAPE OF THAT HAZARD: a block that mutates the value it asserts
  #
  # Re-running a mutating block is merely untidy while the mutation is unrelated
  # to the value being matched. When the block mutates the very quantity under
  # assertion -- a counter it increments, a table it counts after inserting into
  # -- polling cannot converge BY CONSTRUCTION: every retry moves the value one
  # step further from the matcher, and the example burns the whole
  # default_max_wait_time before failing with a "got" that is really just the
  # number of retries. batch6/server_method_spec.rb:71 failed that way with
  # `expected: 5, got: 60` on three cells (#83).
  #
  # The failure is invisible until the first read happens to be wrong, so it
  # surfaces as a rare flake with a wildly inflated value. Write such an example
  # in one of these shapes instead:
  #
  #   * make the block IDEMPOTENT, so re-running it yields the same value --
  #     reset the counter inside the block, or assert a delta rather than an
  #     absolute (batch3/aaa_edge_cases_spec.rb, client_features/react_spec.rb);
  #   * or, where the block already synchronises on a promise, drop to
  #     `evaluate_promise` and a plain `expect(...)`: reading once after the
  #     promise resolves reopens no race (batch6/server_method_spec.rb).
  #
  # ---------------------------------------------------------------------------
  # A SEPARATE HAZARD THE ABOVE DOES NOT COVER: comparing across the two
  # processes
  #
  # Everything above is about re-reading. This one bites a single read.
  #
  # `expect(evaluate_promise { ... }).to eq(SomeModel.some_counter)` reads twice
  # from two different processes: the value the CLIENT resolved, and server state
  # read afterwards, in the example. Nothing ties the two reads to one moment. If
  # anything the client has in flight can still move that server state, the
  # comparison is a race no matter how carefully the first half is read --
  # dropping to `evaluate_promise` fixes the polling hazard and leaves this one
  # untouched.
  #
  # It is easy to leak such a request: any step that reads a server method (or
  # fires an operation) and asserts only the value returned SYNCHRONOUSLY ends
  # with the fetch still outstanding. The next step issues its own, both are
  # evaluated by different Puma threads, and the later one can resolve with the
  # earlier call's value while the counter has already moved past it. On an idle
  # machine every fetch gets its own batch and this never shows; on a loaded CI
  # runner it is an intermittent off-by-one (#100: `expected: 5, got: 4`).
  #
  # The cure is synchronisation, NOT a weaker matcher. Have the step that fires
  # the asynchronous work settle it -- `wait_for_ajax` before the step ends --
  # so the server state is quiescent when the next step reads it. Relaxing the
  # assertion to a delta, or to `be > 0`, would go green whether the client got
  # a fresh value or a stale one, which throws away the only signal the example
  # exists to produce.
  class AsyncExpectationTarget
    INTERVAL = 0.25

    # `first` is evaluated EAGERLY by the caller, before the matcher argument is
    # built. That ordering is load-bearing and was nearly lost: some specs
    # interpolate server state into the matcher itself, e.g.
    #
    #   expect_promise { todo = TodoItem.new(title: 'test4'); ... }
    #     .to match /... #{TodoItem.find_by_title('test4').id} .../
    #
    # Ruby builds the matcher argument before calling `.to`, so with a lazy
    # producer the block had not run yet, the record did not exist, and
    # find_by_title returned nil -> NoMethodError. Evaluating up front preserves
    # the semantics expect_evaluate_ruby has always had; the producer is only for
    # RE-evaluation while polling.
    def initialize(first, &producer)
      @first = first
      @have_first = true
      @producer = producer
    end

    def to(matcher = nil, message = nil, &block)
      target_for(settled(matcher)).to(matcher, message, &block)
    end

    # Single read: see the note above on negative expectations.
    def not_to(matcher = nil, message = nil, &block)
      value, error = fetch
      raise error if error

      target_for(value).not_to(matcher, message, &block)
    end
    alias to_not not_to

    # Anything else behaves exactly as `expect(value)` did before.
    def method_missing(name, *args, &block)
      value, error = fetch
      raise error if error

      target_for(value).public_send(name, *args, &block)
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
      if @have_first
        @have_first = false
        return [@first, nil]
      end

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
