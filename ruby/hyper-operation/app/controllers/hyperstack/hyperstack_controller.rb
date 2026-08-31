# frozen_string_literal: false

# The transport controller (#115).
#
# This used to be defined INSIDE `Hyperstack::Engine.routes.append` in
# lib/hyper-operation/transport/routes.rb, which made the constant's existence
# depend on route-draw timing: Rails draws routes lazily, so
# `Hyperstack::HyperstackController` existed only once something had triggered
# route loading. That is not a property a constant should have.
#
# It broke in CI when #113 resharded hyper-operation's specs from 3 parallel
# processes to 2: controller_op_spec.rb moved to the front of its process group,
# nothing had drawn the routes yet, and every example died with
# `NameError: uninitialized constant Hyperstack::HyperstackController` -- on the
# four Rails 8.0/8.1 cells and none of the Rails 6.1/7.2 ones, because older
# Rails happened to draw routes early enough on its own.
#
# It lived in the routes block for a real reason: `::ApplicationController` is an
# APPLICATION constant and does not exist when this gem is required. A routes
# block is evaluated late enough that it does. An engine's app/controllers gives
# the same lateness without the coupling -- Zeitwerk autoloads this file when
# `Hyperstack::HyperstackController` is first referenced, by which point the
# application's own classes are loadable. Reloading and eager loading are then
# Rails' problem rather than ours, which is why the old
# `unless defined? Hyperstack::HyperstackController` guard is gone: it existed to
# stop a re-evaluated routes block redefining the class, and Zeitwerk makes that
# impossible.
#
# The engine sets `isolate_namespace Hyperstack`, so the `to: 'hyperstack#...'`
# routes in routes.rb resolve to THIS class.

module Hyperstack
  class HyperstackController < ::ApplicationController

    protect_from_forgery except: [:console_update, :execute_remote_api]

    def client_id
      params[:client_id]
    end

    before_action do
      session.delete 'hyperstack-dummy-init' unless session.id
    end

    def session_channel
      "Hyperstack::Session-#{session.id}"
    end

    def regulate(channel)
      unless channel == session_channel # "Hyperstack::Session-#{client_id.split('-').last}"
        Hyperstack::InternalPolicy.regulate_connection(try(:acting_user), channel)
      end
      channel
    end

    def channels(user = acting_user, session_id = session.id)
      Hyperstack::AutoConnect.channels(session_id, user)
    end

    def can_connect?(channel, user = acting_user)
      Hyperstack::InternalPolicy.regulate_connection(
        user,
        Hyperstack::InternalPolicy.channel_to_string(channel)
      )
      true
    rescue
      nil
    end

    def view_permitted?(model, attr, user = acting_user)
      !!model.check_permission_with_acting_user(user, :view_permitted?, attr)
    rescue
      nil
    end

    def viewable_attributes(model, user = acting_user)
      model.attributes.select { |attr| view_permitted?(model, attr, user) }
    end

    [:create, :update, :destroy].each do |op|
      define_method "#{op}_permitted?" do |model, user = acting_user|
        begin
          !!model.check_permission_with_acting_user(user, "#{op}_permitted?".to_sym)
        rescue
          nil
        end
      end
    end

    def debug_console
      if Rails.env.development?
        render inline: "<style>div#console {height: 100% !important;}</style>\n".html_safe
        #  "<div>additional helper methods: channels, can_connect? "\
        #  "viewable_attributes, view_permitted?, create_permitted?, "\
        #  "update_permitted? and destroy_permitted?</div>\n".html_safe
        console
      else
        head :unauthorized
      end
    end

    def subscribe
      channel = regulate params[:channel].gsub('==', '::')
      root_path = request.original_url.gsub(/hyperstack-subscribe.*$/, '')
      Hyperstack::Connection.open(channel, client_id, root_path)
      head :ok
    rescue Exception
      head :unauthorized
    end

    def read
      root_path = request.original_url.gsub(/hyperstack-read.*$/, '')
      data = Hyperstack::Connection.read(client_id, root_path)
      render json: data
    end

    def pusher_auth
      raise unless Hyperstack.transport == :pusher
      channel = regulate params[:channel_name].gsub(/^#{Regexp.quote(Hyperstack.channel)}\-/,'').gsub('==', '::')
      response = Hyperstack.pusher.authenticate(params[:channel_name], params[:socket_id])
      render json: response
    rescue Exception => e
      head :unauthorized
    end

    def action_cable_auth
      raise unless Hyperstack.transport == :action_cable
      channel = regulate params[:channel_name].gsub(/^#{Regexp.quote(Hyperstack.channel)}\-/,'')
      salt = SecureRandom.hex
      authorization = Hyperstack.authorization(salt, channel, client_id)
      render json: {authorization: authorization, salt: salt}
    rescue Exception
      head :unauthorized
    end

    def connect_to_transport
      # PERFORMANCE DEBUGGING (enabled via ENABLE_HYPERSTACK_PROFILING env var)
      profiling_enabled = ENV['ENABLE_HYPERSTACK_PROFILING'].to_s.downcase == 'true'
      start_time = Time.current if profiling_enabled
      Rails.logger.info "[CONTROLLER] connect_to_transport called for channel: #{params[:channel]}, user: #{try(:acting_user)&.class&.name}" if profiling_enabled

      # Enforce the connection policy before (re)registering the channel. Without
      # this, a client the policy denies could resurrect a channel that the refresh
      # sweep just dropped, by hitting this endpoint directly — bypassing the
      # regulate_*_connection policies that `subscribe` enforces. `regulate` skips
      # the per-client session channel and raises AccessViolation on denial. See #12.
      regulate(params[:channel])

      root_path = request.original_url.gsub(/hyperstack-connect-to-transport.*$/, '')

      connection_start = Time.current if profiling_enabled
      result = Hyperstack::Connection.connect_to_transport(params[:channel], client_id, root_path)
      if profiling_enabled
        connection_time = ((Time.current - connection_start) * 1000).round(2)
        Rails.logger.info "[CONTROLLER]   Connection.connect_to_transport took #{connection_time}ms"
      end

      if profiling_enabled
        total_time = ((Time.current - start_time) * 1000).round(2)
        Rails.logger.info "[CONTROLLER] Total connect_to_transport: #{total_time}ms"
      end

      render json: result
    rescue Hyperstack::AccessViolation
      # Connection policy denied this channel for the acting user — refuse to
      # (re)register it (see #12). Distinct from the transport failure below.
      head :unauthorized
    rescue Exception => e
      if profiling_enabled
        error_time = ((Time.current - start_time) * 1000).round(2)
        Rails.logger.error "[CONTROLLER] connect_to_transport FAILED after #{error_time}ms: #{e.message}"
      end
      render status: :service_unavailable, json: {error: e}
    end

    def execute_remote
      parsed_params = JSON.parse(params[:hyperstack_secured_json]).symbolize_keys
      render ServerOp.run_from_client(
        :acting_user,
        self,
        parsed_params[:operation],
        parsed_params[:params].merge(acting_user: acting_user)
      )
    end

    def execute_remote_api
      params.require(:params).permit!
      parsed_params = params[:params].to_h.symbolize_keys
      raise AccessViolation.new(:illegal_remote_api_call) unless parsed_params[:authorization]
      render ServerOp.run_from_client(:authorization, self, params[:operation], parsed_params)
    end

    def console_update # TODO this should just become an execute-remote-api call
      raise unless Rails.env.development?
      authorization = Hyperstack.authorization(params[:salt], params[:channel], params[:data][1][:broadcast_id]) #params[:data].to_json)
      return head :unauthorized if authorization != params[:authorization]
      Hyperstack::Connection.send_to_channel(params[:channel], params[:data])
      head :no_content
    rescue
      head :unauthorized
    end

    def server_up
      head :no_content
    end

  end
end
