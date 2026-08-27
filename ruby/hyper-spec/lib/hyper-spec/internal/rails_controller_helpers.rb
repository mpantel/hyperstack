module HyperSpec
  module Internal
    module RailsControllerHelpers
      def self.included(base)
        base.include ControllerHelpers
        base.include Helpers
        register_harness_route!(base)
      end

      # Register the harness route: GET /<route_root>/:id -> <route_root>#test.
      #
      # Two mechanisms, because the old one stopped working. On Rails 8 the
      # clear!/draw/routes_reloader/finalize! dance below no longer registers the
      # route at all -- every mount/on_client spec fails with
      # `ActionController::RoutingError (No route matches [GET]
      # "/hyper_spec_test/N")`, which on the client side just looks like a page
      # that rendered nothing. `routes.append` is the supported API: appended
      # blocks are re-applied on every route reload and survive finalization, so
      # they coexist with the app's own routes. (#20)
      #
      # It is NOT applied below Rails 8, where the dance is what four green cells
      # have been running; and it is `append`, not `prepend`, even though prepend
      # would match the old ordering -- prepend blocks evaluate inside clear!
      # rather than finalize!, which changed route setup for every gem and broke
      # rails-hyperstack's client-to-server round-trip 3/3 on the rails-8 line.
      #
      # The cost of appending is that a test_app whose routes end in a catch-all
      # (`get '(*foo)' => ...`, which a client-side-router app wants) swallows the
      # harness route and silently renders its own root component instead of the
      # mounted one. Such an app must exclude this path -- see hyper-router's
      # test_app routes.rb for the constraint to copy.
      def self.register_harness_route!(base)
        route_root = base.route_root
        if ::Rails::VERSION::MAJOR >= 8
          ::Rails.application.routes.append do
            get "/#{route_root}/:id", to: "#{route_root}#test"
          end
          ::Rails.application.reload_routes!
          return
        end

        routes = ::Rails.application.routes
        routes.disable_clear_and_finalize = true
        routes.clear!
        routes.draw { get "/#{route_root}/:id", to: "#{route_root}#test" }
        ::Rails.application.routes_reloader.paths.each { |path| load(path) }
        routes.finalize!
        ActiveSupport.on_load(:action_controller) { routes.finalize! }
      ensure
        routes.disable_clear_and_finalize = false if routes
      end

      module Helpers
        def ping!
          head(:no_content)
          nil
        end

        def mount_component!
          prerender = @render_on != :client_only && !HyperSpec.prerendering_disabled?
          @page << '<%= react_component @component_name, @component_params, '\
                   "{ prerender: #{prerender} } %>"
        end

        def application!(file)
          @page << "<%= javascript_include_tag '#{file}' %>"
          @page << opal_bootstrap!(file)
        end

        # opal-rails appended the `Opal.load(...)` bootstrap to the top-level Opal
        # asset it compiled. opal-sprockets alone (the Rails 8 pipeline) does not:
        # it expects the *page* to bootstrap, which is what
        # `Opal::Sprockets.javascript_include_tag` does and what hyper-spec's Rack
        # harness has always done. Without it an Opal asset named by
        # `client_option javascript: '...'` is registered in `Opal.modules` and
        # never executed -- its methods are simply undefined, and the next
        # `evaluate_ruby` dies inside the Opal runtime rather than reporting
        # anything useful. (#20)
        #
        # Nothing to do when opal-rails is in the bundle (it already bootstrapped
        # the asset; doing it twice would re-run it), nor for a plain JS manifest
        # such as `application`, which bootstraps itself and pushes its own name
        # onto OpalLoaded.
        def opal_bootstrap!(file)
          return '' if defined?(::Opal::Rails::Engine)
          return '' unless opal_source_asset?(file)

          "<script type='text/javascript'>\n#{::Opal::Sprockets.load_asset(file)}\n</script>"
        end

        # True when `file` resolves to an Opal source (`.rb`) rather than a
        # JavaScript file or a sprockets manifest. False whenever sprockets cannot
        # tell us (assets precompiled, environment unavailable), which keeps the
        # previous behaviour.
        def opal_source_asset?(file)
          return false unless defined?(::Opal::Sprockets)

          env = ::Rails.application.assets
          return false unless env

          asset = env[file.to_s]
          !asset.nil? && asset.filename.to_s.end_with?('.rb')
        rescue StandardError
          false
        end

        def style_sheet!(file)
          @page << "<%= stylesheet_link_tag '#{file}' %>"
        end

        def deliver!
          @render_params[:inline] = @page
          response.headers['Cache-Control'] = 'max-age=120'
          response.headers['X-Tracking-ID'] = '123456'
          render @render_params
        end

        def server_only?
          @render_on == :server_only
        end
      end
    end
  end
end
