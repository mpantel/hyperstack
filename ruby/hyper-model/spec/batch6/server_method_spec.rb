require 'spec_helper'
require 'rspec-steps'

RSpec::Steps.steps 'server_method', js: true do

  before(:each) do
    require 'pusher'
    require 'pusher-fake'
    Pusher.app_id = "MY_TEST_ID"
    Pusher.key =    "MY_TEST_KEY"
    Pusher.secret = "MY_TEST_SECRET"
    require "pusher-fake/support/base"

    Hyperstack.configuration do |config|
      config.transport = :pusher
      config.channel_prefix = "synchromesh"
      config.opts = {app_id: Pusher.app_id, key: Pusher.key, secret: Pusher.secret, use_tls: false}.merge(PusherFake.configuration.web_options)
    end

    #User.do_not_synchronize
  end

  before(:step) do
    stub_const 'TestApplicationPolicy', Class.new
    TestApplicationPolicy.class_eval do
      always_allow_connection
      regulate_all_broadcasts { |policy| policy.send_all }
      allow_change(to: :all, on: [:create, :update, :destroy]) { true }
    end
    ApplicationController.acting_user = nil
  end

  it "can call a server method" do
    isomorphic do
      TodoItem.class_eval do
        class << self
          attr_writer :server_method_count

          def server_method_count
            @server_method_count ||= 0
          end
        end
        server_method(:test, default: 0) do
          # HYPERSTACK_FORCE_OVERLAP turns the #100 race into a deterministic
          # failure. The flake needs two fetches of this (side effecting) method
          # to be evaluated by different Puma threads at the same time, with the
          # LATER step's evaluated first -- which happens by chance on a loaded
          # CI runner and never on an idle developer machine, where every fetch
          # gets its own batch, one at a time.
          #
          # Setting the variable parks the first invocation that finds the
          # counter at 3 -- the one fired by "returns the default value on the
          # first call" -- until a later invocation has incremented past it. The
          # next step then resolves with THIS call's value while the counter has
          # moved on, reproducing `expected: 5, got: 4` exactly. It is off by
          # default and costs one ENV lookup; with the wait_for_ajax that step
          # now ends with, the overlap cannot form and the run stays green.
          if defined?(::Rails) && ENV['HYPERSTACK_FORCE_OVERLAP'] &&
             TodoItem.server_method_count == 3 &&
             !TodoItem.instance_variable_get(:@forced_overlap_done)
            TodoItem.instance_variable_set(:@forced_overlap_done, true)
            ::Rails.logger.info '[FORCE_OVERLAP] parking this invocation until another increments'
            waited = 0.0
            while TodoItem.server_method_count == 3 && waited < 5
              sleep 0.01
              waited += 0.01
            end
            ::Rails.logger.info "[FORCE_OVERLAP] resuming after #{waited.round(2)}s, count=#{TodoItem.server_method_count}"
          end
          TodoItem.server_method_count += 1
          if defined?(::Rails) && ENV['HYPERSTACK_TRACE_VECTORS']
            ::Rails.logger.info "[TRACE_COUNT] server_method :test invoked -> #{TodoItem.server_method_count} (id=#{id.inspect})"
          end
          TodoItem.server_method_count
        end
      end
      TestModel.server_method(:test) { child_models.count }
    end
    TodoItem.create
    mount 'ServerMethodTester' do
      class ServerMethodTester < HyperComponent
        render(DIV) do
          "test = #{TodoItem.first.test}"
        end
      end
    end
    expect(page).to have_content('test = 1')
  end

  it "can update the server method" do
    evaluate_ruby("TodoItem.first.test!")
    expect(page).to have_content('test = 2')
  end

  it "when updating the server method it returns the current value while waiting for the promise" do
    expect_evaluate_ruby("TodoItem.first.test!").to eq(2)
  end

  it "returns the default value on the first call while waiting for the promise" do
    expect_evaluate_ruby("TodoItem.new.test").to eq(0)
    # Reading `.test` returns the default synchronously and fires the server side
    # fetch ASYNCHRONOUSLY. Nothing above waits for that fetch, so without this
    # wait the step ends with a request still in flight, and the next step issues
    # its own while it is outstanding. Two Puma threads then evaluate the (side
    # effecting) server method concurrently against a plain `count += 1`, which is
    # neither atomic nor ordered: the later step can resolve with the value this
    # step's call produced while the counter has already moved past it. That is
    # exactly the intermittent `expected: 5, got: 4` seen on loaded CI runners,
    # and it reproduces deterministically if this step's invocation is made to
    # park until the next one has incremented (#100).
    #
    # So settle here. Waiting for quiescence -- rather than for a specific value
    # -- also mops up the fetch the PREVIOUS step (`test!`) fires and likewise
    # does not wait for, and keeps this step from leaking work into whatever runs
    # next.
    wait_for_ajax
  end

  it "works with the load method" do
    # The block below increments a server side counter, so it has to be
    # evaluated exactly ONCE. expect_promise polls by re-running its block
    # (#67), and every retry increments the counter again, so an exact value
    # expectation on it can never converge -- the reported "got" degenerates
    # into a count of retry iterations (#83).
    #
    # evaluate_promise reads once, but only after waiting for the promise to
    # resolve, and that resolution is the synchronisation the polling was
    # standing in for here. So reading once reopens no race.
    count_before = TodoItem.server_method_count
    result = evaluate_promise do
      new_todo = TodoItem.new
      ReactiveRecord.load do
        new_todo.test
      end
    end
    # What this step proves is that load resolves with the value the server
    # computed for THIS call: not the default (0), and not a stale earlier
    # value. Comparing against the server's own counter says exactly that,
    # without hard coding how many times the earlier steps happened to call
    # the method -- which is what made the old eq(5) brittle in the first place.
    #
    # `count_before` is read on the server before the block runs and is exact
    # only because the previous step waited for quiescence; this step then fires
    # exactly one fetch, so the value the client resolved must be the one that
    # increment produced. Asserting the delta AND the absolute keeps both halves
    # of the meaning: the delta says the client got THIS call's value rather than
    # an earlier one, the absolute says nothing else moved the counter
    # underneath. Neither is a relaxation -- weakening this to a delta alone (or
    # to `be > 0`) would go green whether the value is fresh or stale, and
    # detecting a stale value is the whole point of the example (#100).
    if ENV['HYPERSTACK_TRACE_VECTORS']
      puts "[TRACE_ASSERT] result=#{result.inspect} count_before=#{count_before.inspect} " \
           "server_method_count=#{TodoItem.server_method_count.inspect}"
    end
    expect(result).to be > 0
    expect(result).to eq(count_before + 1)
    expect(result).to eq(TodoItem.server_method_count)
  end

  it "the server method can access any unsaved associations" do
    expect_promise do
      test_model = TestModel.new
      ChildModel.new(test_model: test_model)
      ReactiveRecord.load do
        test_model.test
      end
    end.to eq(1)
    expect(TestModel.count).to be_zero
    expect(ChildModel.count).to be_zero
  end

  it "will allow remote access to methods" do
    TodoItem.class_eval do
      def foo
        "foo"
      end

      def bar
        "bar"
      end

      def broken
        "broken"
      end

      def defaulted
        "defaulted"
      end
    end
    isomorphic do
      TodoItem.class_eval do
        allow_remote_access_to(:foo, :bar) { acting_user.nil? }
        allow_remote_access_to(:broken) { acting_user.admin? }
        allow_remote_access_to(:dontcallme, defaulted: "loading") { true }
      end
    end
    client_option raise_on_js_errors: :off
    expect { TodoItem.last.foo }.on_client_to be_nil
    expect { Hyperstack::Model.load { TodoItem.last.foo } }.on_client_to eq("foo")
    expect { TodoItem.last.bar }.on_client_to be_nil
    expect { Hyperstack::Model.load { TodoItem.last.bar } }.on_client_to eq("bar")
    expect { Hyperstack::Model.load { TodoItem.last.broken } }.on_client_to be_nil
    expect { TodoItem.last.defaulted }.on_client_to eq "loading"
    expect { Hyperstack::Model.load { TodoItem.last.defaulted } }.on_client_to eq("defaulted")
    # errors = page.driver.browser.manage.logs.get(:browser).select { |m| m.level == "SEVERE" }
    errors = page.driver.browser.logs.get(:browser).select { |m| m.level == "SEVERE" }
    expect(errors.count).to eq(2)
    expect(errors.first.message).to match(/the server responded with a status of 403 \(Forbidden\)/)
  end
end
