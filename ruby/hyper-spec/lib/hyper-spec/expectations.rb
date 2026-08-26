# don't put this in directory lib/rspec/ as that will cause stack overflow with rails/rspec loads
module RSpec
  module Expectations
    class ExpectationTarget; end
    module HyperSpecInstanceMethods
      def self.included(base)
        base.include HyperSpec::Helpers
      end

      def to_on_client(matcher, message = nil, &block)
        evaluate_client(matcher).to(matcher, message, &block)
      end

      alias on_client_to to_on_client
      alias to_then to_on_client
      alias then_to to_on_client

      def to_on_client_not(matcher, message = nil, &block)
        evaluate_client.not_to(matcher, message, &block)
      end

      alias on_client_to_not to_on_client_not
      alias on_client_not_to to_on_client_not
      alias to_not_on_client to_on_client_not
      alias not_to_on_client to_on_client_not
      alias then_to_not to_on_client_not
      alias then_not_to to_on_client_not
      alias to_not_then to_on_client_not
      alias not_to_then to_on_client_not

      private

      def client_value
        source = add_opal_block(@args_str, @target)
        @target.binding.eval("evaluate_ruby(#{source.inspect}, {}, {})")
      end

      # Client state is asynchronous: a value may be broadcast, fetched or
      # recomputed after the block first returns. Reading once and matching once
      # therefore races whatever produces the value -- which is #64, and the same
      # defect class as #61 (a spec that read the DOM before the data arrived).
      #
      # So poll: evaluate, test the matcher, and re-evaluate until it is satisfied
      # or Capybara's timeout expires. This mirrors what Capybara's own matchers do
      # and what `have_field(..., with:)` does for the DOM.
      #
      # Two deliberate limits:
      #
      # * Only POSITIVE expectations poll. Retrying a negative would wait for
      #   something to stop being true, which is a different assertion from the one
      #   written, so `to_on_client_not` keeps reading once.
      # * Block matchers (raise_error, change, ...) are excluded. They expect a
      #   block, not a value, so `matches?` here is meaningless -- and without the
      #   guard a mismatch would poll uselessly for the full timeout before failing.
      #
      # A matching value still costs exactly one evaluation, as before. Only the
      # previously-failing path re-evaluates, so a block with side effects is only
      # re-run in the case that used to fail outright.
      def evaluate_client(matcher = nil)
        value, error = fetch_client_value
        if pollable?(matcher)
          deadline = now + ::Capybara.default_max_wait_time
          until (error.nil? && matched?(matcher, value)) || now >= deadline
            sleep 0.1
            value, error = fetch_client_value
          end
        end
        # Timed out still erroring: re-raise the LAST error, so the failure reads
        # as the real problem rather than as a mismatch against nil.
        raise error if error

        ExpectationTarget.for(value, nil)
      end

      # The client may not merely hold the wrong value -- it may not be ready at
      # all. "uninitialized constant Physician" was a load race: the Opal bundle
      # had not defined the model when the block ran. That raises while EVALUATING,
      # so without this it escapes before the polling above can retry anything.
      #
      # Only JavascriptError is treated as retryable. Retrying every StandardError
      # would swallow real problems and make each one cost the full timeout before
      # failing; a JS error is the one that plausibly means "not yet".
      #
      # The cost is honest: a genuinely broken block now takes the full timeout
      # before reporting, instead of failing at once. That is the price of not
      # being able to tell "broken" from "not ready yet" at the first attempt.
      def fetch_client_value
        [client_value, nil]
      rescue ::StandardError => e
        raise unless retryable_client_error?(e)

        [nil, e]
      end

      def retryable_client_error?(error)
        error.class.name.to_s.include?('Selenium::WebDriver::Error::JavascriptError')
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

    class OnClientWithArgsTarget
      include HyperSpecInstanceMethods

      def initialize(target, args)
        unless args.is_a? Hash
          raise ExpectationNotMetError,
                "You must pass a hash of local var, value pairs to the 'with' modifier"
        end

        @target = target
        @args_str = args.collect do |name, value|
          set_local_var(name, value)
        end.join("\n")
      end
    end

    class BlockExpectationTarget < ExpectationTarget
      include HyperSpecInstanceMethods

      def with(args)
        OnClientWithArgsTarget.new(@target, args)
      end
    end
  end
end
