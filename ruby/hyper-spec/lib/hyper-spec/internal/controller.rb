require 'securerandom'

module HyperSpec
  module Internal
    module Controller
      CACHE_ROOT = '/tmp/hyper-spec-caches'.freeze
      CACHE_EXPIRY = 30

      class << self
        attr_accessor :current_example
        attr_accessor :description_displayed

        # The id is both the last segment of the test URL and the key the mount
        # payload is cached under.  It must therefore be unique across every
        # rspec PROCESS that shares this machine, not merely within one.
        #
        # hyper-model and hyper-operation run their batches as several concurrent
        # rspec processes inside a single container (see the spec:parallel rake
        # task).  The payload cache is a FileCache rooted at a fixed /tmp path
        # whose entry path is MD5(key) and nothing else -- no pid, no port, no
        # run id.  A bare counter restarts at 1 in every process, so two batches
        # both reach "/hyper_spec_test/42", and whichever writes last wins: the
        # other one's page boots with the WRONG batch's compiled client code.
        #
        # Nothing about that is visible.  The payload is structurally valid, so
        # the page renders; it just carries somebody else's code.  Everything
        # that rides in on that code -- `isomorphic do`, `before_mount`,
        # `insert_html`, a block passed to `mount` -- is silently absent for the
        # rest of the example, which is #68 ("uninitialized constant Physician"
        # that never resolves no matter how long the expectation polls).
        #
        # Prefixing a per-process token makes both the cache key and the URL
        # unique.  The random part covers a recycled pid in a container that runs
        # several suites back to back inside the cache's expiry window.  It is
        # recomputed whenever the pid changes, so a forked child cannot inherit
        # the parent's token along with the parent's counter.
        def test_run_token
          if @_hyperspec_private_test_run_token_pid != Process.pid
            @_hyperspec_private_test_run_token_pid = Process.pid
            @_hyperspec_private_test_run_token = "#{Process.pid}-#{SecureRandom.hex(4)}"
          end
          @_hyperspec_private_test_run_token
        end

        def test_id
          @_hyperspec_private_test_id ||= 0
          @_hyperspec_private_test_id += 1
          "#{test_run_token}-#{@_hyperspec_private_test_id}"
        end

        include ActionView::Helpers::JavaScriptHelper

        def current_example_description!
          title = "#{title}...continued." if description_displayed
          self.description_displayed = true
          "#{escape_javascript(current_example.description)}#{title}"
        end

        def file_cache
          @file_cache ||= FileCache.new('cache', CACHE_ROOT, CACHE_EXPIRY, 3).tap do
            purge_stale_entries_at_exit
          end
        end

        # Entry keys used to be a small set of integers that every run reused, so
        # the cache directory stayed bounded on its own.  Now that each run has
        # its own token (see test_id) nothing is ever overwritten, so sweep on the
        # way out.  purge only removes entries older than the expiry, which leaves
        # anything a concurrently-running batch is still using alone, and it races
        # harmlessly against those processes creating entries -- hence the rescue.
        def purge_stale_entries_at_exit
          owner = Process.pid
          at_exit do
            begin
              file_cache.purge if Process.pid == owner
            rescue StandardError
              nil
            end
          end
        end

        def cache_read(key)
          file_cache.get(key)
        end

        def cache_write(key, value)
          file_cache.set(key, value)
        end

        def cache_delete(key)
          file_cache.delete(key)
        rescue StandardError
          nil
        end
      end

      # By default we assume we are operating in a Rails environment and will
      # hook in using a rails controller.  To override this define the
      # HyperSpecController class in your spec helper.  See the rack.rb file
      # for an example of how to do this.

      def hyper_spec_test_controller
        return ::HyperSpecTestController if defined?(::HyperSpecTestController)

        base = if defined? ApplicationController
                 Class.new ApplicationController
               elsif defined? ::ActionController::Base
                 Class.new ::ActionController::Base
               else
                 raise "Unless using Rails you must define the HyperSpecTestController\n"\
                       'For rack apps try requiring hyper-spec/rack.'
               end
        Object.const_set('HyperSpecTestController', base)
      end

      # First insure we have a controller, then make sure it responds to the test method
      # if not, then add the rails specific controller methods.  The RailsControllerHelpers
      # module will automatically add a top level route back to the controller.

      def route_root_for(controller)
        controller ||= hyper_spec_test_controller
        controller.include RailsControllerHelpers unless controller.method_defined?(:test)
        controller.route_root
      end
    end
  end
end
