require 'spec_helper'

describe 'Hyperstack::Operation execution (server side)' do

  before(:each) do
    stub_const 'MyOperation', Class.new(Hyperstack::Operation)
  end

  it "will execute some steps" do
    MyOperation.class_eval do
      param :i
      step { params.i + 1 }
      step { |r| r + params.i }
    end
    expect(MyOperation.run(i: 1).value).to eq 3
  end

  it "will chain promises" do
    MyOperation.class_eval do
      def self.promise
        @promise ||= Promise.new
      end
      param :i
      step { self.class.promise }
      step { |n| params.i + n }
      step { |r| r + params.i }
    end
    expect(MyOperation.run(i: 1).tap { MyOperation.promise.resolve(2) }.value).to eq 4
  end

  it "will chain rejected promises" do
    MyOperation.class_eval do
      def self.promise
        @promise ||= Promise.new
      end
      param :i
      step { self.class.promise }
      step { @took_a_bad_step = true }
      failed { |e| e unless @took_a_bad_step }
    end
    expect(
      MyOperation.run(i: 1)
        .always { |failure| failure }
        .tap { MyOperation.promise.reject("promise rejected") }
        .value
    ).to eq "promise rejected"
  end

  it "will chain promises that raise exceptions" do
    MyOperation.class_eval do
      def self.promise
        @promise ||= Promise.new.then { raise "exception raised" }.tap { |p| p.resolve }
      end
      param :i
      step { self.class.promise }
      step { @took_a_bad_step = true }
      failed { |e| e unless @took_a_bad_step }
    end
    expect(
      MyOperation.run(i: 1)
        .always { |failure| failure.message }
        .value
    ).to eq "exception raised"
  end

  it "will interrupt the promise chain with async" do
    MyOperation.class_eval do
      def self.promise
        @promise ||= Promise.new
      end
      param :i
      step { self.class.promise }
      step { |n| params.i + n }
      step { |r| r + params.i }
      async { 'hi' }
    end
    expect(MyOperation.run(i: 1).value).to eq 'hi'
  end

  it "will continue running after the async" do
    MyOperation.class_eval do
      def self.promise
        @promise ||= Promise.new
      end
      param :i
      step { self.class.promise }
      step { |n| params.i + n }
      step { |r| r + params.i }
      async { 'hi' }
      step { self.class.promise }
    end
    expect(MyOperation.run(i: 1).tap { MyOperation.promise.resolve(2) }.value).to eq 2
  end

  it "will switch to the failure track on an error" do
    MyOperation.class_eval do
      def self.promise
        @promise ||= Promise.new
      end
      param :i
      step { self.class.promise }
      step { |n| params.i + n }
      failed { raise 'i am a' }
      step { MyOperation.dont_call_me }
      failed { |s| raise "#{s} failure" }
    end
    expect(MyOperation).not_to receive(:dont_call_me)
    expect(MyOperation.run(i: 1).tap { MyOperation.promise.resolve('x') }.error.to_s).to eq 'i am a failure'
  end

  it "will begin on the failure track if there are validation errors" do
    MyOperation.class_eval do
      def self.promise
        @promise ||= Promise.new
      end
      param :i
      step { MyOperation.dont_call_me }
      step { |n| params.i + n }
      failed { |s| raise "#{s}! Looks like i am still a" }
      step { MyOperation.dont_call_me }
      failed { |s| "#{s} failure!" }
    end
    "I is required! Looks like i am still a! Looks like i am still a failure!"
    expect(MyOperation).not_to receive(:dont_call_me)
    expect(MyOperation.run.tap { MyOperation.promise.resolve('x') }.error.to_s).to eq 'I is required! Looks like i am still a failure!'
  end

  it "succeed! will skip to the end" do
    MyOperation.class_eval do
      step { succeed! "I succeeded at last!"}
      step { MyOperation.dont_call_me }
      failed { MyOperation.dont_call_me }

    end
    expect(MyOperation).not_to receive(:dont_call_me)
    expect(MyOperation.run.value).to eq 'I succeeded at last!'
  end

  it "succeed! will skip to the end and succeed even on the failure track" do
    MyOperation.class_eval do
      step { fail }
      failed { succeed! "I still can succeed!"}
      step { MyOperation.dont_call_me }
      failed { MyOperation.dont_call_me }
    end
    expect(MyOperation).not_to receive(:dont_call_me)
    expect(MyOperation.run.value).to eq 'I still can succeed!'
    expect(MyOperation.run).to be_resolved
  end

  it "abort! will skip to the end with a failure" do
    MyOperation.class_eval do
      step { abort! "Pride cometh before the fall!"}
      step { MyOperation.dont_call_me }
      failed { MyOperation.dont_call_me}
    end
    expect(MyOperation).not_to receive(:dont_call_me)
    expect(MyOperation.run.error.result).to eq 'Pride cometh before the fall!'
  end

  it "if abort! is given an exception it will return that exception" do
    MyOperation.class_eval do
      step { abort! Exception.new("okay okay okay")}
      step { MyOperation.dont_call_me }
      failed { MyOperation.dont_call_me }
    end
    expect(MyOperation).not_to receive(:dont_call_me)
    expect(MyOperation.run.error.to_s).to eq 'okay okay okay'
  end

  it "can chain an exception after returning" do
    MyOperation.class_eval do
      step { abort! Exception.new("okay okay okay")}
      step { MyOperation.dont_call_me }
      failed { MyOperation.dont_call_me }
    end
    expect(MyOperation).not_to receive(:dont_call_me)
    expect(MyOperation.run.fail { |e| raise "pow" }.error.to_s).to eq 'pow'
  end

  it "can define the step, async and failed callbacks many ways" do
    stub_const 'SayHelloOp', Class.new(Hyperstack::Operation)
    SayHelloOp.class_eval do
      param :xxx
      step { MyOperation.say_hello if params.xxx == 123 }
    end
    MyOperation.class_eval do
      param :xxx
      def say_hello()
        MyOperation.say_hello
      end
      step   { say_hello }
      step   :say_hello
      step   -> () { say_hello }
      step   proc { say_hello }
      step   SayHelloOp # your params will be passed along to SayHelloOp
      async  { say_hello }
      async  :say_hello
      async  -> () { say_hello }
      async  Proc.new { say_hello }
      async  SayHelloOp # your params will be passed along to SayHelloOp
      step   { fail }
      failed { say_hello }
      failed :say_hello
      failed -> () { say_hello }
      failed Proc.new { say_hello }
      failed SayHelloOp # your params will be passed along to SayHelloOp
      failed { succeed! }
    end
    expect(MyOperation).to receive(:say_hello).exactly(15).times
    expect(MyOperation.run(xxx: 123)).to be_resolved
  end

  it "can define class level callbacks" do
    MyOperation.class_eval do
      step(:class) { say_hello }
      step   class: :say_hello
      step   class: -> () { say_hello }
      step   class: proc { say_hello }
      async(:class) { say_hello }
      async  class: :say_hello
      async  class: -> () { say_hello }
      async  class: Proc.new { say_hello }
      step   { fail }
      failed(:class) { say_hello }
      failed class: :say_hello
      failed class: -> () { say_hello }
      failed class: Proc.new { say_hello }
      failed { succeed! }
    end
    expect(MyOperation).to receive(:say_hello).exactly(12).times
    expect(MyOperation.run).to be_resolved
  end

  it 'can provide options different ways' do
    MyOperation.class_eval do
      def say_instance_hello()
        MyOperation.say_hello
      end
      step(scope: :class) { say_hello }
      step scope: :class, run: proc { say_hello }
      step run: :say_instance_hello
      step :say_hello, scope: :class
    end
    expect(MyOperation).to receive(:say_hello).exactly(4).times
    expect(MyOperation.run).to be_resolved
  end
end

# The client-side steps below run as a single shared-session RSpec::Steps
# sequence inside one long-lived browser.  The helpers they rely on
# (get_round_tuit and the DontCallMe / HelloCounter modules) used to be defined
# once via `before(:step) { on_client { ... } }`.  In this spec `on_client` is
# aliased to `before_mount`, which only injects code into the page at *mount*
# time, and because rspec-steps runs the whole sequence within a single example
# the injection effectively happens just once (on the first step's mount).  The
# definitions then have to survive in the browser for the rest of the sequence.
#
# If anything makes hyper-spec re-mount/reload the page mid-sequence the page is
# replaced and the helpers are gone, so a later step blows up with
# `undefined method 'get_round_tuit'`.  insure_page_loaded reloads whenever
# `Opal` momentarily looks absent (a transient `evaluate_script` failure is
# swallowed and treated as "Opal missing"), and the async `after(0.2)` timer in
# get_round_tuit widens the window for such a transient -- hence the
# intermittent, timing-sensitive flake.
#
# Fix: instead of relying on one-time mount injection, (re)define the helpers
# immediately before *every* client evaluation.  We first run insure_page_loaded
# (performing any pending (re)mount up front), then execute the helper
# definitions as their own top-level script -- so get_round_tuit lands as a
# private method on Object and the DontCallMe / HelloCounter modules are top
# level, exactly as the operation step blocks expect.  By the time the real
# evaluation runs, Opal is already loaded so its own insure_page_loaded is a
# no-op and cannot wipe the freshly-defined helpers.  This covers both
# evaluation paths used below (expect_evaluate_ruby / expect_promise blocks and
# `expect { }.on_client_to`), since both funnel through `evaluate_ruby`.
#
# (Defining the helpers as a separate top-level script rather than prepending
# their source to the evaluated expression matters: internal_evaluate_ruby wraps
# the evaluated code in `(...).tap { ... }`, and a `def`/`module` nested inside
# that expression is not installed on Object, so a later step block running on
# the operation instance would not see get_round_tuit.)
module HyperspecOperationClientHelpers
  CLIENT_HELPERS = <<~RUBY
    def get_round_tuit(value)
      Promise.new.tap { |p| after(0.2) { value == :reject ? p.reject("promise rejected") : p.resolve(value) } }
             .then { |v| value == :exception ? raise("exception raised") : v }
    end
    module DontCallMe
      def called?
        @called
      end
      def dont_call_me
        @called = true
      end
    end
    module HelloCounter
      def hello_count
        @called || 0
      end
      def say_hello
        @called ||= 0
        @called += 1
      end
    end
  RUBY

  module Prepended
    # Both client-eval entry points used below (expect_evaluate_ruby /
    # expect_promise and `expect { }.on_client_to`) funnel through
    # `evaluate_ruby`, so that is the seam we hook.  (Note: `evaluate_ruby` is an
    # alias of internal_evaluate_ruby, and the alias binds to the original method
    # body -- overriding internal_evaluate_ruby would NOT be seen by callers that
    # invoke the alias, so we must override `evaluate_ruby` itself.)
    def evaluate_ruby(*args, &block)
      # Perform any pending (re)mount first, then (re)define the helpers as a
      # standalone top-level script so they are always present for the
      # evaluation that super is about to run.
      insure_page_loaded
      page.execute_script(opal_compile(CLIENT_HELPERS))
      super(*args, &block)
    end
  end

  def self.included(base)
    base.prepend(Prepended)
  end
end

RSpec::Steps.steps 'Hyperstack::Operation execution (client side)', js: true do

  include HyperspecOperationClientHelpers

  it "will execute some steps" do
    expect_evaluate_ruby do
      Class.new(Hyperstack::Operation) do
        param :i
        step { params.i + 1 }
        step { |r| r + params.i }
      end.run(i: 1).value
    end.to eq 3
  end

  it "will chain promises" do
    expect_promise do
      Class.new(Hyperstack::Operation) do
        param :i
        step { get_round_tuit(2) }
        step { |n| params.i + n }
        step { |r| r + params.i }
      end.run(i: 1)
    end.to eq 4
  end

  it "will chain rejected promises" do
    expect do
      Class.new(Hyperstack::Operation) do
        param :i
        step { get_round_tuit(:reject) }
        step { @took_a_bad_step = true }
        failed { |e| e unless @took_a_bad_step }
      end.run(i: 1).always { |failure| failure }
    end.on_client_to eq "promise rejected"
  end

  it "will chain promises that raise exceptions" do
    expect do
      Class.new(Hyperstack::Operation) do
        param :i
        step { get_round_tuit(:exception) }
        step { @took_a_bad_step = true }
        failed { |e| e unless @took_a_bad_step }
      end.run(i: 1).always { |failure| failure }
    end.on_client_to eq "exception raised"
  end

  it "will interrupt the promise chain with async" do
    expect_promise do
      Class.new(Hyperstack::Operation) do
        param :i
        step { get_round_tuit(2) }
        step { |n| params.i + n }
        step { |r| r + params.i }
        async { 'hi' }
      end.run(i: 1)
    end.to eq 'hi'
  end

  it "will interrupt the promise chain with async" do
    expect_promise do
      Class.new(Hyperstack::Operation) do
        param :i
        step { get_round_tuit(2) }
        step { |n| params.i + n }
        step { |r| r + params.i }
        async { 'hi' }
      end.run(i: 1)
    end.to eq 'hi'
  end

  it "will continue running after the async" do
    expect_promise do
      Class.new(Hyperstack::Operation) do
        param :i
        step { get_round_tuit(2) }
        step { |n| params.i + n }
        step { |r| r + params.i }
        async { 'hi' }
        step { get_round_tuit(2) }
      end.run(i: 1)
    end.to eq 2
  end

  it "will switch to the failure track on an error" do
    expect_promise do
      operation = Class.new(Hyperstack::Operation) do
        extend DontCallMe
        param :i
        step { get_round_tuit('x') }
        step { |n| params.i + n }
        failed { raise 'i am a' }
        step { self.class.dont_call_me }
        failed { |s| raise "#{s.message} failure" }
      end
      operation.run(i: 1).always { |e| e.message unless operation.called? }
    end.to eq 'i am a failure'
  end

  it "will begin on the failure track if there are validation errors" do
    expect_promise do
      operation = Class.new(Hyperstack::Operation) do
        extend DontCallMe
        param :i
        step   { self.class.dont_call_me }
        step   { |n| params.i + n }
        failed { |s| raise "#{s.message}! Looks like i am still a" }
        step   { self.class.dont_call_me }
        failed { |s| "#{s.message} failure!" }
      end
      operation.run.always { |e| e unless operation.called? }
    end.to eq 'i is required! Looks like i am still a failure!'
  end

  it "succeed! will skip to the end" do
    expect_promise do
      operation = Class.new(Hyperstack::Operation) do
        extend DontCallMe
        step { succeed! "I succeeded at last!"}
        step { MyOperation.dont_call_me }
        failed { MyOperation.dont_call_me}
      end
      operation.run.then { |e| e unless operation.called? }
    end.to eq 'I succeeded at last!'
  end

  it "succeed! will skip to the end and succeed even on the failure track" do
    expect_evaluate_ruby do
      operation = Class.new(Hyperstack::Operation) do
        extend DontCallMe
        step { fail }
        failed { succeed! "I still can succeed!"}
        step { self.class.dont_call_me }
        failed { self.class.dont_call_me }
      end
      result = operation.run
      [operation.called?, result.value, result.resolved?]
    end.to eq [nil, 'I still can succeed!', true]
  end

  it "abort! will skip to the end with a failure" do
    expect_evaluate_ruby do
      operation = Class.new(Hyperstack::Operation) do
        extend DontCallMe
        step { abort! "Pride cometh before the fall!"}
        step { self.class.dont_call_me }
        failed { self.class.dont_call_me}
      end
      result = operation.run
      [operation.called?, result.rejected?, result.error.result]
    end.to eq [nil, true, 'Pride cometh before the fall!']
  end

  it "if abort! is given an exception it will return that exception" do
    expect_evaluate_ruby do
      operation = Class.new(Hyperstack::Operation) do
        extend DontCallMe
        step { abort! Exception.new("okay okay okay")}
        step { MyOperation.dont_call_me }
        failed { MyOperation.dont_call_me}
      end
      result = operation.run
      [operation.called?, result.rejected?, result.error.message]
    end.to eq [nil, true, 'okay okay okay']
  end


  it "can define the step, async and failed callbacks many ways" do
    expect_evaluate_ruby do

      TestOperation = Class.new(Hyperstack::Operation)

      class SayHelloOp < Hyperstack::Operation
        param :xxx
        step { TestOperation.say_hello if params.xxx == 123 }
      end

      TestOperation.class_eval do
        param :xxx
        extend HelloCounter
        def say_hello
          self.class.say_hello
        end
        step   { say_hello }
        step   :say_hello
        step   -> () { say_hello }
        step   proc { say_hello }
        step   SayHelloOp # your params will be passed along to SayHelloOp
        async  { say_hello }
        async  :say_hello
        async  -> () { say_hello }
        async  Proc.new { say_hello }
        async  SayHelloOp # your params will be passed along to SayHelloOp
        step   { fail }
        failed { say_hello }
        failed :say_hello
        failed -> () { say_hello }
        failed Proc.new { say_hello }
        failed SayHelloOp # your params will be passed along to SayHelloOp
        failed { succeed! }
      end
      result = TestOperation.run(xxx: 123)
      [TestOperation.hello_count, result.resolved?]
    end.to eq [15, true]
  end

  it "can define class level callbacks" do
    expect_evaluate_ruby do
      operation = Class.new(Hyperstack::Operation) do
        extend HelloCounter
        step(:class) { say_hello }
        step   class: :say_hello
        step   class: -> () { say_hello }
        step   class: proc { say_hello }
        async(:class) { say_hello }
        async  class: :say_hello
        async  class: -> () { say_hello }
        async  class: Proc.new { say_hello }
        step   { fail }
        failed(:class) { say_hello }
        failed class: :say_hello
        failed class: -> () { say_hello }
        failed class: Proc.new { say_hello }
        failed { succeed! }
      end
      [operation.run.resolved?, operation.hello_count]
    end.to eq [true, 12]
  end

  it 'can provide options different ways' do
    expect_evaluate_ruby do
      operation = Class.new(Hyperstack::Operation) do
        extend HelloCounter
        def say_instance_hello()
          self.class.say_hello
        end
        step(scope: :class) { say_hello }
        step scope: :class, run: proc { say_hello }
        step run: :say_instance_hello
        step :say_hello, scope: :class
      end
      [operation.run.resolved?, operation.hello_count]
    end.to eq [true, 4]
  end
end
