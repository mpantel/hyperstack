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
        # Rails 6.1.7.x carries the same safe-load backport, so the pre-7.1
        # branch below needs the permitted classes just as much -- it just needs
        # them spelled differently, since `serialize` there takes no `yaml:`
        # option. A bare `serialize :data` on a patched 6.1 dumps fine and then
        # raises on the way back in:
        #   Psych::DisallowedClass: Tried to load unspecified class:
        #   ActiveSupport::HashWithIndifferentAccess
        # from ActiveRecord::Coders::YAMLColumn#yaml_load.
        #
        # That went unnoticed because it was unreachable: per #103 the
        # hyperstack_queued_messages table was never created on Rails 6.1 at all,
        # so nothing was ever queued there and nothing was ever read back. The
        # two defects were nested -- fixing #103 turned the queued path on, and
        # this is what was waiting underneath. The raise also presents from
        # inside restore_transaction_record_state during `rolledback!`, i.e. at
        # an unrelated Model.create call site rather than at the queue read,
        # which makes it thoroughly misleading in an application. (#104)
        #
        # Rails 6.1's `serialize` accepts any object responding to dump/load, so
        # the same list is applied on the column rather than by widening
        # config.active_record.yaml_column_permitted_classes -- #44's reasoning
        # stands: hyperstack's own table should not require the host application
        # to widen a global list.
        class PermittedYAMLCoder
          def self.dump(obj)
            return if obj.nil?

            YAML.dump(obj)
          end

          def self.load(yaml)
            return if yaml.nil?
            return yaml unless yaml.is_a?(String) && yaml.start_with?('---')

            # aliases: true because a payload can legitimately repeat a value --
            # the same time or model name across records -- and Psych emits an
            # alias for it, which safe_load rejects unless told otherwise.
            YAML.safe_load(yaml, permitted_classes: PERMITTED_YAML_CLASSES, aliases: true)
          end
        end

        if ::ActiveRecord.version >= Gem::Version.new('7.1')
          serialize :data, coder: YAML, yaml: { permitted_classes: PERMITTED_YAML_CLASSES }
        else
          serialize :data, PermittedYAMLCoder
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
