module Hyperstack
  ::Hyperstack::Engine.routes.append do
    Hyperstack.initialize_policies

    module ::WebConsole
      class Middleware
      private
        def acceptable_content_type?(headers)
          Mime::Type.parse(headers['Content-Type'] || '').first == Mime[:html]
        end
      end
    end if defined? ::WebConsole::Middleware

    # The purpose of this is to prevent massive amounts of logging
    # if using simple polling. If polling is on then only actual messages
    # with content will be shown, other wise the log message is dropped.
    module ::Rails
      module Rack
        class Logger < ActiveSupport::LogSubscriber
          unless method_defined? :pre_hyperstack_call
            alias pre_hyperstack_call call
            def call(env)
              if Hyperstack.transport == :simple_poller && env['PATH_INFO'] && env['PATH_INFO'].include?('/hyperstack-read/')
                Rails.logger.silence do
                  pre_hyperstack_call(env)
                end
              else
                pre_hyperstack_call(env)
              end
            end
          end
        end
      end
    end if defined?(::Rails::Rack::Logger)

    match 'execute_remote',
          to: 'hyperstack#execute_remote', via: :post
    match 'execute_remote_api',
          to: 'hyperstack#execute_remote_api', via: :post

    # match 'hyperstack-subscribe',
    #       to: 'hyperstack#subscribe', via: :get
    # match 'hyperstack-read/:subscriber',
    #       to: 'hyperstack#read',      via: :get
    match 'hyperstack-subscribe/:client_id/:channel',
          to: 'hyperstack#subscribe', via: :get
    match 'hyperstack-read/:client_id',
          to: 'hyperstack#read', via: :get
    match 'hyperstack-pusher-auth',
          to: 'hyperstack#pusher_auth', via: :post
    match 'hyperstack-action-cable-auth/:client_id/:channel_name',
          to: 'hyperstack#action_cable_auth', via: :post
    match 'hyperstack-connect-to-transport/:client_id/:channel',
          to: 'hyperstack#connect_to_transport', via: :get
    match 'console',
          to: 'hyperstack#debug_console', via: :get
    match 'console_update',
          to: 'hyperstack#console_update', via: :post
    match 'server_up',
          to: 'hyperstack#server_up', via: :get
  end
end
