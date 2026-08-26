# frozen_string_literal: true

require_relative 'redis/connection'
require_relative 'redis/queued_message'

module Hyperstack
  module ConnectionAdapter
    module Redis
      class << self
        def transport
          Hyperstack::Connection.transport
        end

        def active
          if Hyperstack.on_server?
            Connection.expired.each(&:destroy)
            refresh_connections if Connection.needs_refresh?
          end

          Connection.all.map(&:channel).uniq
        end

        def open(channel, session = nil, root_path = nil)
          self.root_path = root_path

          Connection.find_or_create_by(channel: channel, session: session)
        end

        def send_to_channel(channel, data)
          Connection.pending_for(channel).each do |connection|
            QueuedMessage.create(connection_id: connection.id, data: data)
          # A message is waiting for this client, so this is not an abandoned
          # half-open connection -- extend the handshake window instead of letting
          # it expire and taking the queued message with it.
          #
          # `expire_new_connection_in` (default 10s) exists to reap connections
          # that `open` and never `connect_to_transport`. But the reaping is
          # `Connection.expired.delete_all`, which destroys the queued messages
          # too, so a broadcast issued while a client is still handshaking was
          # silently lost if the handshake ran past the window -- routine on a
          # loaded server. Diagnosed in #70: passing runs pushed, failing runs
          # queued and then dropped.
          #
          # Extending only when a message arrives keeps the leak protection for
          # genuinely idle half-open connections.
            connection.update(expires_at: Time.current + transport.expire_new_connection_in)
          end

          transport.send_data(channel, data) if Connection.exists?(channel: channel, session: nil)
        end

        def read(session, root_path)
          self.root_path = root_path

          Connection.where(session: session).each do |connection|
            connection.update(expires_at: Time.current + transport.expire_polled_connection_in)
          end

          messages = QueuedMessage.for_session(session)
          data = messages.map(&:data)
          messages.each(&:destroy)
          data
        end

        def connect_to_transport(channel, session, root_path)
          # PERFORMANCE DEBUGGING (enabled via ENABLE_HYPERSTACK_PROFILING env var)
          profiling_enabled = ENV['ENABLE_HYPERSTACK_PROFILING'].to_s.downcase == 'true'
          overall_start = Time.current if profiling_enabled
          Rails.logger.info "[REDIS_ADAPTER] connect_to_transport called for channel: #{channel}, session: #{session[0..20]}..." if profiling_enabled

          step_start = Time.current if profiling_enabled
          self.root_path = root_path
          Rails.logger.info "[REDIS_ADAPTER]   set root_path took #{((Time.current - step_start) * 1000).round(2)}ms" if profiling_enabled

          step_start = Time.current if profiling_enabled
          connection = Connection.find_by(channel: channel, session: session)
          Rails.logger.info "[REDIS_ADAPTER]   Connection.find_by took #{((Time.current - step_start) * 1000).round(2)}ms, found: #{!connection.nil?}" if profiling_enabled

          if connection
            step_start = Time.current if profiling_enabled
            messages = connection.messages.map(&:data)
            Rails.logger.info "[REDIS_ADAPTER]   connection.messages.map took #{((Time.current - step_start) * 1000).round(2)}ms, count: #{messages.size}" if profiling_enabled

            step_start = Time.current if profiling_enabled
            connection.destroy
            Rails.logger.info "[REDIS_ADAPTER]   connection.destroy took #{((Time.current - step_start) * 1000).round(2)}ms" if profiling_enabled
          else
            messages = []
          end

          step_start = Time.current if profiling_enabled
          open(channel)
          Rails.logger.info "[REDIS_ADAPTER]   open(channel) took #{((Time.current - step_start) * 1000).round(2)}ms" if profiling_enabled

          if profiling_enabled
            overall_time = ((Time.current - overall_start) * 1000).round(2)
            Rails.logger.info "[REDIS_ADAPTER] Total connect_to_transport: #{overall_time}ms"
          end

          messages
        end

        def disconnect(channel)
          Connection.find_by(channel: channel, session: nil)&.destroy
        end

        def root_path=(path)
          QueuedMessage.root_path = path if path
        end

        def root_path
          QueuedMessage.root_path
        rescue
          nil
        end

        def refresh_connections
          refresh_started_at = Time.current
          channels = transport.refresh_channels
          next_refresh = refresh_started_at + transport.refresh_channels_every

          # Filter channels to only those still allowed by connection policies
          allowed_channels = channels.select do |channel|
            channel_allowed_by_policy?(channel)
          end

          allowed_channels.each do |channel|
            connection = Connection.find_by(channel: channel, session: nil)
            connection.update(refresh_at: next_refresh) if connection
          end

          # Disconnect channels that are no longer allowed by policy
          (channels - allowed_channels).each do |channel|
            transport.disconnect_channel(channel) if transport.respond_to?(:disconnect_channel)
          end

          Connection.inactive.each(&:destroy)
        end

        def channel_allowed_by_policy?(channel)
          # Try to get acting_user from ApplicationController if it exists (test environment)
          acting_user = begin
            ApplicationController.acting_user if defined?(ApplicationController) && ApplicationController.respond_to?(:acting_user)
          rescue
            nil
          end

          # Check if the channel is allowed by the policy
          begin
            Hyperstack::InternalPolicy.regulate_connection(acting_user, channel)
            true
          rescue Hyperstack::AccessViolation
            # Explicit policy denial — a connection regulation actively rejected this
            # user (or a non-AR/unknown channel class). Drop it. See #9.
            false
          rescue => e
            # No applicable connection regulation (raises a bare "connection failed")
            # or an unexpected error — allow by default rather than disconnect an
            # unregulated/possibly-legitimate channel.
            true
          end
        end
      end
    end
  end
end
