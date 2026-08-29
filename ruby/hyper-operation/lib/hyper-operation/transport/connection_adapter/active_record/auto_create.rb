# frozen_string_literal: true

module Hyperstack
  module ConnectionAdapter
    module ActiveRecord
      module AutoCreate
        def table_exists?
          # works with both rails 4 and 5 without deprecation warnings
          if connection.respond_to?(:data_sources)
            connection.data_sources.include?(table_name)
          else
            connection.tables.include?(table_name)
          end
        end

        # Deliberately NOT gated on Hyperstack.on_server? (#103).
        #
        # `on_server?` is `defined?(Rails::Server)`, which answers "was this
        # process started by `rails server`" -- and that is false under
        # Capybara's in-process server, a bare `puma`/`rackup`, Passenger, and
        # any rake task. Gating table creation on it meant these two tables --
        # which have no migration and exist ONLY because this method creates
        # them -- were never created in those processes. ConnectionAdapter::
        # ActiveRecord.active then returns [] behind its own `table_exists?`
        # guard, which is indistinguishable from "nobody is listening", so every
        # broadcast was dropped with no error anywhere.
        #
        # Whether this process happens to be the one serving requests has
        # nothing to do with whether the tables need to exist. `on_server?`
        # remains the right question for send_data/dispatch, which use it to
        # decide between broadcasting directly and forwarding to the running
        # server over HTTP; it was never the right question here. Creating the
        # tables from a console or a rake task is harmless -- create_table is a
        # no-op once they exist -- and is how they reach schema.rb at all.
        def needs_init?
          return false if Hyperstack.transport == :none

          !table_exists?
        rescue StandardError
          # No usable database: an asset precompile, a build container, or a
          # boot before db:create. There is nothing to create and this must not
          # become a boot failure -- the old on_server? gate happened to cover
          # these cases too, and dropping it must not lose that.
          false
        end

        def create_table(**options, &block)
          connection.create_table(table_name, **options, &block) if needs_init?
        end
      end
    end
  end
end
