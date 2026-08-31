require 'spec_helper'

# Regression coverage for #112.
#
# #105 made `Hyperstack.on_server?` answer honestly. This is about the branch it
# selects. `send_data`, `dispatch` and `Broadcast.after_commit` used to forward a
# broadcast to the running server over HTTP whenever this process was not the one
# serving requests -- but whether the *local* branch works is decided by the
# transport and its adapter, not by the process. On :simple_poller, :pusher, or
# :action_cable over a shared cable backend, a rake task can deliver perfectly
# well; it was instead POSTing to `console_update`, which is
# `raise unless Rails.env.development?`, getting a 401 nobody read, and skipping
# `Connection.send_to_channel` -- so no QueuedMessage rows were written and the
# dispatch was gone.
#
# Browser-free by design, in the style of on_server_spec.rb: set the transport
# and the cable adapter, make `on_server?` false, and assert which branch runs.
describe 'broadcast forwarding' do
  # spec_helper sets `Hyperstack.on_server = true` for every example (the rspec
  # process *is* the Capybara server) and the suite has served plenty of requests
  # by now. Both have to be put back.
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

  # A console, a rake task, a `rails runner`, a Sidekiq worker: not the server,
  # but the app has served requests before so the server's root path is on file.
  def off_server_with_a_server_to_forward_to!
    Hyperstack.on_server = false
    allow(Hyperstack::Connection).to receive(:root_path).and_return('http://example.com/')
  end

  # `transport` is a define_setting whose writer requires files and adds imports;
  # stubbing the reader asks the same question without the side effects.
  def using_transport(name)
    allow(Hyperstack).to receive(:transport).and_return(name)
  end

  def using_cable_adapter(name)
    allow(Hyperstack).to receive(:action_cable_adapter).and_return(name)
  end

  describe 'Hyperstack.direct_delivery?' do
    it 'is true for the polling transport, which delivers by writing rows' do
      using_transport :simple_poller
      expect(Hyperstack.direct_delivery?).to be true
    end

    it 'is true for pusher, which delivers by an outbound API call' do
      using_transport :pusher
      expect(Hyperstack.direct_delivery?).to be true
    end

    it 'is true with no transport configured at all' do
      using_transport :none
      expect(Hyperstack.direct_delivery?).to be true
    end

    %w[redis postgresql].each do |adapter|
      it "is true for action_cable over the shared #{adapter} backend" do
        using_transport :action_cable
        using_cable_adapter adapter
        expect(Hyperstack.direct_delivery?).to be true
      end
    end

    # The one row of the table that genuinely needs the HTTP hop: the cable
    # server's subscriber list lives in the web process's memory.
    %w[async inline test].each do |adapter|
      it "is false for action_cable over the process-local #{adapter} adapter" do
        using_transport :action_cable
        using_cable_adapter adapter
        expect(Hyperstack.direct_delivery?).to be false
      end
    end

    it 'assumes a shared backend when the cable adapter cannot be read' do
      using_transport :action_cable
      using_cable_adapter nil
      # Guessing "process-local" would send the broadcast to a route that
      # refuses it in production, which is the failure this exists to remove.
      expect(Hyperstack.direct_delivery?).to be true
    end

    it 'lets the connection adapter veto direct delivery' do
      using_transport :simple_poller
      allow(Hyperstack::Connection).to receive(:direct_delivery?).and_return(false)
      expect(Hyperstack.direct_delivery?).to be false
    end
  end

  describe 'Hyperstack.action_cable_adapter' do
    # test_app's config/cable.yml says `async` for the test environment, so this
    # reads the real Rails config rather than a stub.
    it 'reads the cable adapter configured for this environment' do
      expect(Hyperstack.action_cable_adapter).to eq 'async'
    end

    it 'answers nil rather than raising when the cable config is unreadable' do
      allow(::ActionCable).to receive(:server).and_raise(RuntimeError, 'no cable.yml')
      expect(Hyperstack.action_cable_adapter).to be_nil
    end
  end

  describe 'Hyperstack.forward_to_server?' do
    it 'is false on the server whatever the transport' do
      Hyperstack.on_server = true
      allow(Hyperstack::Connection).to receive(:root_path).and_return('http://example.com/')
      using_transport :action_cable
      using_cable_adapter 'async'
      expect(Hyperstack.forward_to_server?).to be false
    end

    it 'is false off the server when this process can deliver directly' do
      off_server_with_a_server_to_forward_to!
      using_transport :simple_poller
      expect(Hyperstack.forward_to_server?).to be false
    end

    it 'is true off the server when this process cannot deliver directly' do
      off_server_with_a_server_to_forward_to!
      using_transport :action_cable
      using_cable_adapter 'async'
      expect(Hyperstack.forward_to_server?).to be true
    end

    # #105: with no server on file there is nothing to forward to, and queueing
    # locally beats raising 'no server running'.
    it 'is false when there is no server to forward to' do
      Hyperstack.on_server = false
      allow(Hyperstack::Connection).to receive(:root_path).and_return(nil)
      using_transport :action_cable
      using_cable_adapter 'async'
      expect(Hyperstack.forward_to_server?).to be false
    end
  end

  # The defect itself: what a production rake task's ServerOp dispatch actually
  # does.
  describe 'dispatch from a process that is not the server' do
    before(:each) { off_server_with_a_server_to_forward_to! }

    it 'delivers locally on a transport that can be delivered to locally' do
      using_transport :simple_poller

      expect(Hyperstack).not_to receive(:send_to_server)
      expect(Hyperstack::Connection)
        .to receive(:send_to_channel).with('Test', [:dispatch, { channel: 'Test' }])

      Hyperstack.dispatch(channel: 'Test')
    end

    it 'still forwards on action_cable over a process-local cable adapter' do
      using_transport :action_cable
      using_cable_adapter 'async'

      expect(Hyperstack::Connection).not_to receive(:send_to_channel)
      expect(Hyperstack)
        .to receive(:send_to_server).with('Test', [:dispatch, { channel: 'Test' }])

      Hyperstack.dispatch(channel: 'Test')
    end

    it 'writes the queued rows a polling client reads, instead of dropping them' do
      using_transport :simple_poller

      # The whole point: the forwarding branch skipped send_to_channel, so no
      # QueuedMessage row was ever written and the dispatch was gone.
      Hyperstack::Connection.open('DirectDeliveryTestChannel', 'session-112')
      expect(Hyperstack).not_to receive(:send_to_server)

      expect { Hyperstack.dispatch(channel: 'DirectDeliveryTestChannel') }
        .to change { Hyperstack::Connection.read('session-112', nil).count }.by(1)
    end
  end

  describe 'send_data from a process that is not the server' do
    before(:each) { off_server_with_a_server_to_forward_to! }

    let(:packet) { [:dispatch, { channel: 'Test', broadcast_id: 'abc' }] }

    it 'does not forward on a transport that can be delivered to locally' do
      using_transport :simple_poller

      expect(Hyperstack).not_to receive(:send_to_server)
      Hyperstack.send_data('Test', packet)
    end

    it 'still forwards on action_cable over a process-local cable adapter' do
      using_transport :action_cable
      using_cable_adapter 'async'

      expect(Hyperstack).to receive(:send_to_server).with('Test', packet)
      Hyperstack.send_data('Test', packet)
    end
  end

  # `send_to_server` returned the Net::HTTP response and nothing read it, so the
  # 401 that `console_update` answers outside development was indistinguishable
  # from a delivered broadcast. That is what made this a silent defect. (#112)
  describe 'a forward the server refuses' do
    def stub_forward_response(response)
      allow(Hyperstack::Connection).to receive(:root_path).and_return('http://example.com/')
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(response)
    end

    it 'raises rather than reporting success' do
      stub_forward_response(Net::HTTPUnauthorized.new('1.1', '401', 'Unauthorized'))

      expect { Hyperstack.send_to_server('Test', [:dispatch, { broadcast_id: 'abc' }]) }
        .to raise_error(/401/)
    end

    it 'names the channel and says the message was not sent' do
      stub_forward_response(Net::HTTPUnauthorized.new('1.1', '401', 'Unauthorized'))

      expect { Hyperstack.send_to_server('Test', [:dispatch, { broadcast_id: 'abc' }]) }
        .to raise_error(/channel Test.*NOT been sent/m)
    end

    it 'is quiet when the server accepts it' do
      # console_update answers `head :no_content`.
      stub_forward_response(Net::HTTPNoContent.new('1.1', '204', 'No Content'))

      expect { Hyperstack.send_to_server('Test', [:dispatch, { broadcast_id: 'abc' }]) }
        .not_to raise_error
    end
  end
end
