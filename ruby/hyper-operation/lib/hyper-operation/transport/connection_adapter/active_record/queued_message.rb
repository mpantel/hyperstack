# frozen_string_literal: true

require_relative 'auto_create'

module Hyperstack
  module ConnectionAdapter
    module ActiveRecord
      class QueuedMessage < ::ActiveRecord::Base
        extend AutoCreate

        self.table_name = 'hyperstack_queued_messages'

        do_not_synchronize

        # What gets stored in `data` is one of hyperstack's own broadcast
        # messages -- a message name plus the serialized record params -- not
        # application data. Those params are always an
        # ActiveSupport::HashWithIndifferentAccess and routinely carry times.
        PERMITTED_YAML_CLASSES = [
          Symbol, Time, Date, DateTime, BigDecimal,
          ActiveSupport::HashWithIndifferentAccess,
          ActiveSupport::TimeWithZone,
          ActiveSupport::TimeZone
        ].freeze

        # Rails 7.1 requires an explicit coder for serialize; the historical
        # default was YAML, so keep YAML for backward compatibility with data
        # already stored in existing tables.
        #
        # It also routes YAML through ActiveRecord::Coders::YAMLColumn's safe
        # coder, which refuses to *dump* anything outside
        # `config.active_record.yaml_column_permitted_classes` -- and that
        # defaults to `[Symbol]`. So on a stock Rails 7.1+ app every queued
        # broadcast died with
        #   Psych::DisallowedClass: Tried to dump unspecified class:
        #   ActiveSupport::HashWithIndifferentAccess
        # Queuing is what happens whenever a broadcast reaches a client whose
        # transport connection has not finished its handshake (see
        # Connection.pending_for), so this took out :simple_poller completely and
        # made :action_cable drop the broadcast whenever the change beat the
        # websocket handshake -- reliably on a loaded CI runner, essentially never
        # on a fast local one. hyperstack's own table should not depend on the
        # host application widening a global list, so declare the classes it
        # queues on the column itself. (#44)
        if ::ActiveRecord.version >= Gem::Version.new('7.1')
          serialize :data, coder: YAML, yaml: { permitted_classes: PERMITTED_YAML_CLASSES }
        else
          serialize :data
        end

        belongs_to :hyperstack_connection,
                   class_name:  'Hyperstack::ConnectionAdapter::ActiveRecord::Connection',
                   foreign_key: 'connection_id',
                   optional:    true

        scope :for_session,
              ->(session) { joins(:hyperstack_connection).where('session = ?', session) }

        # For simplicity we use QueuedMessage with connection_id 0
        # to store the current path which is used by consoles to
        # communicate back to the server. The belongs_to connection
        # therefore must be optional.

        default_scope { where('connection_id IS NULL OR connection_id != 0') }

        def self.root_path=(path)
          unscoped.find_or_create_by(connection_id: 0).update(data: path)
        end

        def self.root_path
          unscoped.find_or_create_by(connection_id: 0).data
        end
      end
    end
  end
end
