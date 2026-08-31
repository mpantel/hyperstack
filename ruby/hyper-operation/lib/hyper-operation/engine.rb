module Hyperstack
  # Records the one fact `Hyperstack.on_server?` cannot guess: this process is
  # serving requests. (#105)
  #
  # `on_server?` used to be `defined?(Rails::Server)`, which is true only under
  # `rails server` -- not under Passenger, a bare `puma`/`rackup`, or Capybara's
  # in-process server. Rather than enumerate rack servers, watch for the thing
  # that actually distinguishes a server process from a console or a rake task:
  # a request going through it.
  #
  # This sits in the app's middleware stack, so it runs for every request
  # regardless of which controller (or engine) ends up handling it, and it runs
  # before the router -- a broadcast issued from the very first request already
  # sees the flag set.
  class MarkServerProcess
    def initialize(app)
      @app = app
    end

    def call(env)
      Hyperstack.serving_requests!
      @app.call(env)
    end
  end

  class Engine < ::Rails::Engine
    isolate_namespace Hyperstack

    # This does NOT create Hyperstack::Engine. hyperstack-config does, in
    # lib/hyperstack/rail_tie.rb, which hyper-operation.rb:2 requires long before
    # it reaches here -- so the superclass matches, Ruby REOPENS that class, and
    # `Rails::Engine.inherited` does not fire a second time. That hook is the only
    # thing that ever sets `called_from` (railties engine.rb:360), and the engine's
    # root is `find_root(called_from)` (engine.rb:552). The one shared
    # Hyperstack::Engine is therefore rooted at ruby/hyperstack-config, and every
    # path it derives -- `paths.add "app/controllers"` included -- points there,
    # not here.
    #
    # That is why moving HyperstackController into this gem's
    # app/controllers/hyperstack/hyperstack_controller.rb did not by itself make it
    # autoloadable: the directory belongs to no engine's root, so nothing ever
    # registered it, and every request died with
    #   ActionController::RoutingError: uninitialized constant Hyperstack::HyperstackController
    # on all ten cells (pipeline 6930). The old definition inside
    # `Engine.routes.append` at least existed once routes had been drawn, which is
    # the timing coupling #115 set out to remove.
    #
    # So register the directory explicitly. In the class body rather than an
    # initializer: this runs at require time, unambiguously before
    # `set_autoload_paths` reads the list and freezes it, with no initializer
    # ordering to get right. `config.autoload_paths` is an appendable Array in
    # every Rails we build against -- memoized from `paths.autoload_paths` on 6.1,
    # an initially-empty user array on 7.2/8.x that `all_autoload_paths` unions
    # with the derived ones.
    #
    # autoload_paths and not eager_load_paths, deliberately: this class subclasses
    # ::ApplicationController, an APPLICATION constant, so it must not be built
    # until something asks for it. On-demand is also the lifetime the routes-block
    # definition had, so this changes WHEN the constant can be resolved (always,
    # rather than only after a route draw) without changing what must already
    # exist when it is finally built. (#115)
    config.autoload_paths << File.expand_path('../../app/controllers', __dir__)
    config.generators do |g|
      g.test_framework      :rspec,        :fixture => false
      g.fixture_replacement :factory_bot, :dir => 'spec/factories'
      g.assets false
      g.helper false
    end

    initializer 'hyperstack.mark_server_process' do |app|
      app.middleware.use Hyperstack::MarkServerProcess
    end
  end
end
