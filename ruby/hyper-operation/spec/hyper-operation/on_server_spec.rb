require 'spec_helper'

# Regression coverage for #105.
#
# `Hyperstack.on_server?` was `defined?(Rails::Server)`, a constant that exists
# only when the process was started through `rails server`. Under Passenger, a
# container running `bundle exec puma` or `rackup`, or Capybara's in-process
# server, it does not exist -- so the predicate answered *false from inside the
# server itself*, and `send_data`, `dispatch` and `Broadcast.after_commit` all
# took their "I am a console, forward to the running server over HTTP" branch.
# In production that POST lands on `console_update`, which is `raise unless
# Rails.env.development?`, so the broadcast is dropped with a 401 nobody reads;
# in development the far end calls `send_to_channel` -> `send_data`, which asks
# the same false question again and posts back, until the timeout fires.
#
# Deliberately browser-free, and deliberately not dependent on how this process
# was started -- that dependence is the defect. `without_rails_server` takes the
# constant away so the assertions mean the same thing on every cell of the
# matrix, including Rails 8, whose boot path defines `Rails::Server` where 6.1
# and 7.2 do not (see #103).
describe 'Hyperstack.on_server?' do
  # spec_helper sets `Hyperstack.on_server = true` for every example (the rspec
  # process *is* the Capybara server), and by now the suite has served plenty of
  # requests. Both have to be put back.
  around(:each) do |example|
    saved_setting = Hyperstack.on_server
    saved_observed = Hyperstack.instance_variable_get(:@serving_requests)
    begin
      example.run
    ensure
      Hyperstack.on_server = saved_setting
      Hyperstack.instance_variable_set(:@serving_requests, saved_observed)
    end
  end

  # The state a process is in before it has served anything and before anyone
  # has told it what it is: a console, a rake task, or a web server that has
  # just booted.
  def freshly_booted!
    Hyperstack.on_server = nil
    Hyperstack.instance_variable_set(:@serving_requests, nil)
  end

  def without_rails_server
    return yield unless ::Rails.const_defined?(:Server, false)

    server = ::Rails.const_get(:Server, false)
    ::Rails.send(:remove_const, :Server)
    begin
      yield
    ensure
      ::Rails.const_set(:Server, server)
    end
  end

  def serve_one_request!
    Hyperstack::MarkServerProcess.new(->(_env) { [200, {}, []] }).call({})
  end

  describe 'detection' do
    it 'is false in a process that has not served a request and was not started by `rails server`' do
      without_rails_server do
        freshly_booted!
        expect(Hyperstack.on_server?).to be false
      end
    end

    it 'is true once the process has served a request, with no Rails::Server anywhere' do
      without_rails_server do
        freshly_booted!
        expect(Hyperstack.on_server?).to be false

        serve_one_request!

        # This is the whole of #105: a puma/Passenger/Capybara-served app used to
        # be stuck on the false above for its entire life.
        expect(Hyperstack.on_server?).to be true
      end
    end

    # The one above drives the middleware class directly; this one drives the
    # application's real stack, so it also proves the engine initializer put the
    # marker in it and put it in front of the router.
    it 'is set by a request through the real application middleware stack' do
      without_rails_server do
        freshly_booted!
        expect(Hyperstack.on_server?).to be false

        begin
          Rack::MockRequest.new(Rails.application).get('/')
        rescue StandardError
          # A 404 or a routing error is fine -- the marker sits in front of the
          # router, so whether anything is mounted at / is beside the point.
        end

        expect(Hyperstack.on_server?).to be true
      end
    end

    it 'stays true for the rest of the process once a request has been served' do
      without_rails_server do
        freshly_booted!
        serve_one_request!
        3.times { expect(Hyperstack.on_server?).to be true }
      end
    end

    it 'still recognises `rails server`' do
      freshly_booted!
      stub_const('Rails::Server', Class.new)
      expect(Hyperstack.on_server?).to be true
    end

    it 'recognises Passenger' do
      without_rails_server do
        freshly_booted!
        stub_const('PhusionPassenger', Module.new)
        expect(Hyperstack.on_server?).to be true
      end
    end
  end

  describe 'the explicit setting' do
    it 'wins over detection when false' do
      serve_one_request!
      Hyperstack.on_server = false
      expect(Hyperstack.on_server?).to be false
    end

    it 'wins over detection when true' do
      without_rails_server do
        freshly_booted!
        Hyperstack.on_server = true
        expect(Hyperstack.on_server?).to be true
      end
    end

    it 'hands back to detection when set to nil' do
      without_rails_server do
        freshly_booted!
        Hyperstack.on_server = false
        expect(Hyperstack.on_server?).to be false

        Hyperstack.on_server = nil
        serve_one_request!
        expect(Hyperstack.on_server?).to be true
      end
    end
  end

  # The consequences the predicate actually controls. The transport here is
  # :simple_poller (test_app), so the direct branch of send_data is a no-op --
  # what matters is that it is not the `send_to_server` branch.
  describe 'what it routes' do
    let(:packet) { [:dispatch, { channel: 'Test', broadcast_id: 'abc' }] }

    before(:each) do
      allow(Hyperstack::Connection).to receive(:root_path).and_return('http://example.com/')
    end

    it 'send_data does not post the server a message from itself' do
      without_rails_server do
        freshly_booted!
        serve_one_request!

        expect(Hyperstack).not_to receive(:send_to_server)
        Hyperstack.send_data('Test', packet)
      end
    end

    it 'dispatch delivers locally rather than posting to itself' do
      without_rails_server do
        freshly_booted!
        serve_one_request!

        expect(Hyperstack).not_to receive(:send_to_server)
        expect(Hyperstack::Connection)
          .to receive(:send_to_channel).with('Test', [:dispatch, { channel: 'Test' }])
        Hyperstack.dispatch(channel: 'Test')
      end
    end

    it 'still forwards from a console, which is the branch that is meant to exist' do
      without_rails_server do
        freshly_booted!

        # #112 narrowed the forwarding branch to the one case that needs it:
        # action_cable over a cable adapter whose subscriber list is inside the
        # web process. On this test_app's :simple_poller a console delivers
        # locally instead -- see direct_delivery_spec.rb.
        allow(Hyperstack).to receive(:transport).and_return(:action_cable)
        allow(Hyperstack).to receive(:action_cable_adapter).and_return('async')

        expect(Hyperstack).to receive(:send_to_server).with('Test', packet)
        Hyperstack.send_data('Test', packet)
      end
    end
  end

  # send_data used to forward on `!on_server?` alone, while dispatch and
  # Broadcast.after_commit both also required a root_path. A rake task on a box
  # where the app had never served a request therefore raised 'no server
  # running' out of send_to_server instead of queueing locally. (#105)
  it 'does not raise when there is no server to forward to' do
    without_rails_server do
      freshly_booted!
      allow(Hyperstack::Connection).to receive(:root_path).and_return(nil)

      expect { Hyperstack.send_data('Test', [:dispatch, { channel: 'Test' }]) }
        .not_to raise_error
    end
  end

  # Guards the guard: if the marker middleware ever stops being installed, every
  # test above still passes (they call it directly) while a real deployment goes
  # straight back to answering false.
  it 'installs the marker middleware in the application stack' do
    expect(Rails.application.middleware.map(&:name))
      .to include('Hyperstack::MarkServerProcess')
  end
end
