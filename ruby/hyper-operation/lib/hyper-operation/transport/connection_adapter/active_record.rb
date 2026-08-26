# frozen_string_literal: true

require_relative 'active_record/connection'
require_relative 'active_record/queued_message'

module Hyperstack
  module ConnectionAdapter
    module ActiveRecord
      class << self
        def build_tables
          Connection.create_table(force: :cascade) do |t|
            t.string   :channel
            t.string   :session
            t.datetime :created_at
            t.datetime :expires_at
            t.datetime :refresh_at
          end

          QueuedMessage.create_table(force: :cascade) do |t|
            t.text    :data
            t.integer :connection_id
          end
        end

        def transport
          Hyperstack::Connection.transport
        end

        def active
          # if table doesn't exist then we are either calling from within
          # a migration or from a console before the server has ever started
          # in these cases there are no channels so we return nothing
          return [] unless Connection.table_exists?

          if Hyperstack.on_server?
            Connection.expired.delete_all
            refresh_connections if Connection.needs_refresh?
          end

          Connection.all.pluck(:channel).uniq
        rescue ::ActiveRecord::StatementInvalid
          []
        end

        def open(channel, session = nil, root_path = nil)
          self.root_path = root_path

          Connection.find_or_create_by(channel: channel, session: session)
        end

        def send_to_channel(channel, data)
          Connection.pending_for(channel).each do |connection|
            QueuedMessage.create(data: data, hyperstack_connection: connection)
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

          Connection.where(session: session)
                    .update_all(expires_at: Time.current + transport.expire_polled_connection_in)

          QueuedMessage.for_session(session).destroy_all.pluck(:data)
        end

        def connect_to_transport(channel, session, root_path)
          self.root_path = root_path

          if (connection = Connection.find_by(channel: channel, session: session))
            messages = connection.messages.pluck(:data)
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
          # if the QueuedMessage table doesn't exist then we are either calling from within
          # a migration or from a console before the server has ever started
          # in these cases there is no root path to the server
          QueuedMessage.root_path if QueuedMessage.table_exists?
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

          Connection.inactive.delete_all
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
