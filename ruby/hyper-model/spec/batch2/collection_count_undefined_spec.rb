require 'spec_helper'
require 'test_components'

# Regression spec for https://github.com/hyperstack-org/hyperstack/issues/31
#
# Under Opal 1.8.3 / Ruby 3.4 an UNLOADED ReactiveRecord::Collection could have
# `count` resolve to raw JS `undefined` instead of a value that safely answers
# `zero?`.  Callers (`empty?`, the ancestor check in sync_collection_with_parent,
# etc.) would then crash on first render with:
#   Uncaught TypeError: Cannot read properties of undefined (reading '$zero?')
# which left the component rendering a blank page.
#
# These specs mount a component that calls `empty?` / `count` on a collection
# that is unloaded on first render and assert that the component renders its
# content rather than blowing up.

describe "collection count is undefined-safe (issue #31)" do

  context "client tests", js: true do

    before(:all) do
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
    end

    before(:each) do
      # spec_helper resets the policy system after each test so we have to setup
      # before each test
      stub_const 'TestApplication', Class.new
      stub_const 'TestApplicationPolicy', Class.new
      TestApplicationPolicy.class_eval do
        always_allow_connection
        regulate_all_broadcasts { |policy| policy.send_all }
        allow_change(to: :all, on: [:create, :update, :destroy]) { true }
      end
      size_window(:small, :portrait)
    end

    it "empty? does not crash when the collection count is undefined" do
      # `empty?` is the caller from issue #31 that crashed with
      #   Cannot read properties of undefined (reading '$zero?')
      # because it does `count.zero?`.  We force the collection's count to resolve
      # to raw JS undefined (the reported symptom) and assert empty? answers true
      # instead of raising.  Before the fix this raises inside `count.zero?`.
      mount "ProbeComponentForEmpty" do
        class ProbeComponentForEmpty < HyperComponent
          render(:div) { "ready".span(id: :sentinel) }
        end
      end
      page.should have_css("#sentinel")
      expect_evaluate_ruby do
        collection = TestModel.all
        fake = `{ '$count': function() { return undefined; } }`
        collection.instance_variable_set(:@collection, fake)
        collection.instance_variable_set(:@count, nil)
        collection.instance_variable_set(:@dummy_collection, nil)
        collection.empty?
      end.to be(true)
    end

    it "_count_internal coerces an undefined count to 0" do
      # Directly exercise the undefined -> 0 coercion at the unit level inside the
      # client runtime.  We take a collection and force the branch that computes
      # the count to return raw JS `undefined` (the symptom reported in #31), then
      # assert _count_internal answers 0 (so `zero?` is safe) instead of leaking
      # undefined.  Before the fix this raises on `result.zero?`.
      mount "ProbeComponent" do
        class ProbeComponent < HyperComponent
          render(:div) { "ready".span(id: :sentinel) }
        end
      end
      page.should have_css("#sentinel")
      expect_evaluate_ruby do
        collection = TestModel.all
        # Drive the `elsif @collection` branch and make its `.count` resolve to
        # raw JS undefined, mimicking the unloaded-count symptom from issue #31.
        fake = `{ '$count': function() { return undefined; } }`
        collection.instance_variable_set(:@collection, fake)
        collection.instance_variable_set(:@count, nil)
        collection.instance_variable_set(:@dummy_collection, nil)
        result = collection._count_internal(false)
        [result, result.zero?]
      end.to eq([0, true])
    end
  end
end
