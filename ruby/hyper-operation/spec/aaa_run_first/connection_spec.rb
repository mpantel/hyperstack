require 'spec_helper'

%i[redis active_record].each do |adapter|
  describe Hyperstack::Connection do
    if adapter == :active_record
      if ActiveRecord::Base.connection.respond_to? :data_sources
        it 'creates the tables (rails 5.x)' do
          ActiveRecord::Base.connection.data_sources.should include('hyperstack_connections')
          ActiveRecord::Base.connection.data_sources.should include('hyperstack_queued_messages')

          expect(described_class.column_names)
            .to match(%w[id channel session created_at expires_at refresh_at])
        end
      else
        it 'creates the tables (rails 4.x)' do
          ActiveRecord::Base.connection.tables.should include('hyperstack_connections')
          ActiveRecord::Base.connection.tables.should include('hyperstack_queued_messages')

          expect(described_class.column_names)
            .to match(%w['id channel session created_at expires_at refresh_at])
        end
      end
    end

    before(:all) do
      Hyperstack.configuration do |config|
        config.connection = { adapter: adapter }
      end
    end

    before(:each) do
      Timecop.return
    end

    it 'creates the messages queue' do
      channel = described_class.adapter::Connection.create
      channel.messages << described_class.adapter::QueuedMessage.new

      channel.messages.should eq(described_class.adapter::QueuedMessage.all)
    end

    it 'can set the root path' do
      described_class.root_path = 'foobar'
      expect(described_class.root_path).to eq('foobar')
    end

    it 'adding new connection' do
      described_class.open('TestChannel', 0)

      expect(described_class.active).to eq(['TestChannel'])
    end

    it 'new connections expire' do
      described_class.open('TestChannel', 0)
      expect(described_class.active).to eq(['TestChannel'])
      Timecop.travel(Time.now + described_class.transport.expire_new_connection_in)
      expect(described_class.active).to eq([])
    end

    it 'a queued message keeps its pending connection alive (#70)' do
      # A broadcast to a client that has opened a connection but not yet
      # completed connect_to_transport is QUEUED. Before the fix, that queued
      # message was destroyed along with its connection when
      # expire_new_connection_in elapsed, so a broadcast issued while a client was
      # still handshaking was silently lost -- routine on a loaded server.
      #
      # Timed deliberately: the message arrives just BEFORE the original window
      # closes, and we then travel past that original window. With the fix the
      # connection expires relative to the queued message instead, so it survives.
      opened_at = Time.now
      window = described_class.transport.expire_new_connection_in
      described_class.open('TestChannel', '0')

      Timecop.travel(opened_at + window - 1)
      described_class.send_to_channel('TestChannel', 'data')

      Timecop.travel(opened_at + window + 1)
      expect(described_class.active).to eq(['TestChannel'])
      expect(described_class.read('0', 'path')).to eq(['data'])
    end

    it 'can send and read data from a channel' do
      described_class.open('TestChannel', '0')
      described_class.open('TestChannel', '1')
      described_class.open('AnotherChannel', '0')
      described_class.send_to_channel('TestChannel', 'data')
      expect(described_class.read('0', 'path')).to eq(['data'])
      expect(described_class.read('0', 'path')).to eq([])
      expect(described_class.read('1', 'path')).to eq(['data'])
      expect(described_class.read('1', 'path')).to eq([])
      expect(described_class.read('0', 'path')).to eq([])
    end

    it 'will update the expiration time after reading' do
      described_class.open('TestChannel', '0')
      described_class.send_to_channel('TestChannel', 'data')
      described_class.read('0', 'path')
      Timecop.travel(Time.now + described_class.transport.expire_new_connection_in)

      expect(described_class.active).to eq(['TestChannel'])
    end

    it 'will expire a polled connection' do
      described_class.open('TestChannel', '0')
      described_class.send_to_channel('TestChannel', 'data')
      described_class.read('0', 'path')
      Timecop.travel(Time.now + described_class.transport.expire_polled_connection_in)

      expect(described_class.active).to eq([])
    end

    context 'after connecting to the transport' do
      before(:each) do
        described_class.open('TestChannel', '0')
        described_class.open('TestChannel', '1')
        described_class.send_to_channel('TestChannel', 'data')
      end

      it 'will pass any pending data back' do
        expect(described_class.connect_to_transport('TestChannel', '0', nil)).to eq(['data'])
      end

      it 'will have the root path set for console access' do
        described_class.connect_to_transport('TestChannel', '0', 'some_path')
        expect(Hyperstack::Connection.root_path).to eq('some_path')
      end

      it 'the channel will still be active even after initial connection time is expired' do
        described_class.connect_to_transport('TestChannel', '0', nil)
        Timecop.travel(Time.now + described_class.transport.expire_new_connection_in)
        expect(described_class.active.sort).to eq(['TestChannel'].sort)
      end

      it 'will only effect the session being connected' do
        described_class.connect_to_transport('TestChannel', '0', nil)
        expect(described_class.read('1', 'path')).to eq(['data'])
      end

      it 'will begin refreshing the channel list' do
        allow(Hyperstack).to receive(:refresh_channels) { ['AnotherChannel'] }
        described_class.open('AnotherChannel', 0)
        described_class.connect_to_transport('TestChannel', '0', nil)
        described_class.connect_to_transport('AnotherChannel', '0', nil)

        expect(described_class.active.sort).to eq(%w[TestChannel AnotherChannel].sort)

        Timecop.travel(Time.now + described_class.transport.refresh_channels_every)

        expect(described_class.active.sort).to eq(['AnotherChannel'].sort)
      end

      it 'refreshing will not effect channels not connected to the transport' do
        allow(Hyperstack).to receive(:refresh_channels) { ['AnotherChannel'] }
        described_class.open('AnotherChannel', 0)
        described_class.connect_to_transport('TestChannel', 0, nil)
        Timecop.travel(Time.now + described_class.transport.refresh_channels_every - 1)
        described_class.read('1', 'path')
        described_class.connect_to_transport('AnotherChannel', 0, nil)
        expect(described_class.active.sort).to eq(%w[TestChannel AnotherChannel].sort)
        Timecop.travel(Time.now + 1)
        described_class.active
        expect(described_class.active.sort).to eq(%w[TestChannel AnotherChannel].sort)
      end

      it 'refreshing will not effect channels added during the refresh' do
        allow(Hyperstack).to receive(:refresh_channels) do
          described_class.connect_to_transport('TestChannel', 0, nil)
          ['AnotherChannel']
        end
        described_class.open('AnotherChannel', '0')
        Timecop.travel(Time.now + described_class.transport.refresh_channels_every)
        described_class.read('0', 'path')
        described_class.connect_to_transport('AnotherChannel', '0', nil)
        expect(described_class.active.sort).to eq(%w[TestChannel AnotherChannel].sort)
        described_class.open('TestChannel', '2')
        expect(described_class.active.sort).to eq(%w[TestChannel AnotherChannel].sort)
      end

      it 'sends messages to the transport as well as open channels' do
        expect(Hyperstack).to receive(:send_data).with('TestChannel', 'data2')
        described_class.connect_to_transport('TestChannel', '0', nil)
        described_class.send_to_channel('TestChannel', 'data2')
        expect(described_class.read('1', 'path').sort).to eq(%w[data data2].sort)
      end
    end
  end
end
