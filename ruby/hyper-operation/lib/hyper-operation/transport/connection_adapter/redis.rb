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
          self.root_path = root_path

          if (connection = Connection.find_by(channel: channel, session: session))
            messages = connection.messages.map(&:data)
            connection.destroy
          else
            messages = []
          end

          open(channel)

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
          rescue
            false
          end
        end
      end
    end
  end
end
