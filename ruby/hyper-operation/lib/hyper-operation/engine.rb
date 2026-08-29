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
