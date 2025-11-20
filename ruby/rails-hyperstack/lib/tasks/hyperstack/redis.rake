# frozen_string_literal: true

namespace :hyperstack do
  namespace :redis do
    desc "Clean up expired connections and orphaned messages from Redis"
    task cleanup: :environment do
      require 'hyperstack'

      # Only proceed if using Redis adapter
      unless Hyperstack.connection && Hyperstack.connection[:adapter] == 'redis'
        puts "Hyperstack is not using Redis adapter. Skipping cleanup."
        next
      end

      require 'hyper-operation/transport/connection_adapter/redis'

      puts "=" * 80
      puts "Hyperstack Redis Cleanup"
      puts "=" * 80
      puts "Started at: #{Time.current}"
      puts

      # Get initial counts
      initial_connections = Hyperstack::ConnectionAdapter::Redis::Connection.all.count
      initial_messages = Hyperstack::ConnectionAdapter::Redis::QueuedMessage.all.count

      puts "Initial counts:"
      puts "  Connections: #{initial_connections}"
      puts "  Queued Messages: #{initial_messages}"
      puts

      # Clean up expired connections
      puts "Cleaning up expired connections..."
      expired = Hyperstack::ConnectionAdapter::Redis::Connection.expired
      expired_count = expired.count
      expired.each(&:destroy)
      puts "  Deleted #{expired_count} expired connections"

      # Clean up inactive connections (stale refresh_at)
      puts "Cleaning up inactive connections..."
      inactive = Hyperstack::ConnectionAdapter::Redis::Connection.inactive
      inactive_count = inactive.count
      inactive.each(&:destroy)
      puts "  Deleted #{inactive_count} inactive connections"

      # Clean up orphaned messages (messages without valid connections)
      puts "Cleaning up orphaned messages..."
      all_messages = Hyperstack::ConnectionAdapter::Redis::QueuedMessage.all
      valid_connection_ids = Hyperstack::ConnectionAdapter::Redis::Connection.all.map(&:id)
      orphaned_count = 0

      all_messages.each do |message|
        # Skip the root_path message (connection_id: 0)
        next if message.connection_id == '0' || message.connection_id == 0

        unless valid_connection_ids.include?(message.connection_id)
          message.destroy
          orphaned_count += 1
        end
      end
      puts "  Deleted #{orphaned_count} orphaned messages"

      # Get final counts
      final_connections = Hyperstack::ConnectionAdapter::Redis::Connection.all.count
      final_messages = Hyperstack::ConnectionAdapter::Redis::QueuedMessage.all.count

      puts
      puts "Final counts:"
      puts "  Connections: #{final_connections} (#{initial_connections - final_connections} deleted)"
      puts "  Queued Messages: #{final_messages} (#{initial_messages - final_messages} deleted)"
      puts
      puts "Cleanup completed at: #{Time.current}"
      puts "=" * 80
    end

    desc "Display Redis statistics"
    task stats: :environment do
      require 'hyperstack'

      unless Hyperstack.connection && Hyperstack.connection[:adapter] == 'redis'
        puts "Hyperstack is not using Redis adapter."
        next
      end

      require 'hyper-operation/transport/connection_adapter/redis'

      puts "=" * 80
      puts "Hyperstack Redis Statistics"
      puts "=" * 80

      # Connection stats
      connections = Hyperstack::ConnectionAdapter::Redis::Connection.all
      puts "Connections: #{connections.count}"

      if connections.any?
        permanent = connections.select { |c| c.session.nil? }
        temporary = connections.select { |c| c.session.present? }
        expired = Hyperstack::ConnectionAdapter::Redis::Connection.expired
        inactive = Hyperstack::ConnectionAdapter::Redis::Connection.inactive

        puts "  Permanent: #{permanent.count}"
        puts "  Temporary: #{temporary.count}"
        puts "  Expired: #{expired.count}"
        puts "  Inactive: #{inactive.count}"

        # Age statistics
        if connections.any?
          oldest = connections.min_by { |c| c.created_at }
          newest = connections.max_by { |c| c.created_at }

          puts
          puts "Age:"
          puts "  Oldest: #{oldest.created_at} (#{((Time.current - oldest.created_at) / 86400).round(1)} days ago)"
          puts "  Newest: #{newest.created_at} (#{((Time.current - newest.created_at) / 60).round(1)} minutes ago)"
        end
      end

      # Message stats
      messages = Hyperstack::ConnectionAdapter::Redis::QueuedMessage.all
      puts
      puts "Queued Messages: #{messages.count}"

      if messages.any?
        # Count orphaned messages
        valid_connection_ids = connections.map(&:id)
        orphaned = messages.count do |msg|
          msg.connection_id != '0' && msg.connection_id != 0 &&
            !valid_connection_ids.include?(msg.connection_id)
        end

        puts "  Orphaned: #{orphaned} (messages without valid connections)"
      end

      puts "=" * 80
    end

    desc "Force delete all Redis data (use with caution)"
    task reset: :environment do
      require 'hyperstack'

      unless Hyperstack.connection && Hyperstack.connection[:adapter] == 'redis'
        puts "Hyperstack is not using Redis adapter."
        next
      end

      print "WARNING: This will delete ALL Hyperstack connections and messages from Redis. Continue? (y/N): "
      response = STDIN.gets.chomp

      unless response.downcase == 'y'
        puts "Aborted."
        next
      end

      require 'hyper-operation/transport/connection_adapter/redis'

      puts "Deleting all connections and messages..."
      Hyperstack::ConnectionAdapter::Redis::Connection.destroy_all
      Hyperstack::ConnectionAdapter::Redis::QueuedMessage.destroy_all

      puts "Redis data cleared."
    end
  end
end
