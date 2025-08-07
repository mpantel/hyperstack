module Hyperstack
  module Internal
    module Component
      module Rails
        class ComponentLoader
          attr_reader :v8_context
          private :v8_context

          def initialize(v8_context)
            unless v8_context
              raise ArgumentError.new('Could not obtain ExecJS runtime context')
            end
            @v8_context = v8_context
          end

          def load(file = components)
            return true if loaded?
            opal_code = opal(file)
            return false unless opal_code
            !!v8_context.eval(opal_code)
          end

          def load!(file = components)
            return true if loaded?
            self.load(file)
          ensure
            raise "No Hyperstack components found in #{components}" unless loaded?
          end

          def loaded?
            # Check if React is available - this is required for component rendering
            !!v8_context.eval('typeof React !== "undefined"')
          rescue ::ExecJS::Error
            false
          end

          private

          def components
            opts = ::Rails.configuration.react.server_renderer_options
            return opts[:files].first.gsub(/.js$/,'') if opts && opts[:files]
            'components'
          end

          def opal(file)
            Opal::Sprockets.load_asset(file)
          rescue StandardError => e
            # If asset cannot be loaded, return nil
            nil
          end
        end
      end
    end
  end
end
