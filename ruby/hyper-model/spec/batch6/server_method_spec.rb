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
        server_method(:test, default: 0) { TodoItem.server_method_count += 1 }
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
    expect(result).to be > 0
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
