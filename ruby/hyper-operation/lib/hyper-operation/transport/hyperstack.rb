# Provides the configuration and the two basic routines for the server
# to indicate that records have changed: after_change and after_destroy
module Hyperstack

  def self.initialize_policies
    reset_operations unless @config_reset_called
  end

  on_config_reset do
    reset_operations
  end

  def self.reset_operations
    @config_reset_called = true
    Rails.configuration.tap do |config|
      # config.eager_load_paths += %W(#{config.root}/app/hyperstack/models)
      # config.autoload_paths += %W(#{config.root}/app/hyperstack/models)
      # config.assets.paths << ::Rails.root.join('app', 'hyperstack').to_s
      config.after_initialize { Connection.build_tables if Connection.build_tables? }
    end
    Object.send(:remove_const, :Application) if @fake_application_defined
    @fake_application_defined = false
    policy = begin
      Object.const_get 'ApplicationPolicy'
    rescue LoadError
    rescue NameError => e
      raise e unless e.message =~ /uninitialized constant ApplicationPolicy/
    end
    application = begin
      Object.const_get('Application')
    rescue LoadError
    rescue NameError => e
      raise e unless e.message =~ /uninitialized constant Application/
    end if policy
    if policy && !application
      Object.const_set 'Application', Class.new
      @fake_application_defined = true
    end
    begin
      Object.const_get 'Hyperstack::ApplicationPolicy'
    rescue LoadError
    rescue NameError => e
      raise e unless e.message =~ /uninitialized constant Hyperstack::ApplicationPolicy/
    end
    @pusher = nil
  end

  define_setting(:transport, :none) do |transport|
    if transport == :action_cable
      require 'hyper-operation/transport/action_cable'
      import 'action_cable', client_only: true if Rails.configuration.hyperstack.auto_config
    elsif transport == :pusher
      require 'pusher'
      import 'hyperstack/pusher', client_only: true if Rails.configuration.hyperstack.auto_config
      opts[:refresh_channels_every] = nil if opts[:refresh_channels_every] == :never
    else
      opts[:refresh_channels_every] = nil if opts[:refresh_channels_every] == :never
    end
  end

  define_setting(:send_to_server_timeout, 10)

  define_setting :opts, {}
  define_setting :channel_prefix, 'synchromesh'
  define_setting :client_logging, true
  define_setting :connect_session, true

  define_setting(:connection, { adapter: :active_record }) do |connection|
    if connection[:adapter] == :redis
      require 'redis'

      connection[:redis_url] ||= 'redis://127.0.0.1:6379/0'
    end
  end

  def self.app_id
    opts[:app_id] || Pusher.app_id if transport == :pusher
  end

  def self.key
    opts[:key] || Pusher.key if transport == :pusher
  end

  def self.secret
    opts[:secret] || Pusher.secret if transport == :pusher
  end

  def self.cluster
    # mt1 is the default Pusher app cluster
    opts[:cluster] || 'mt1' if transport == :pusher
  end

  # Whether the JS client should use TLS. Three spellings are accepted because
  # `opts` is one hash handed to two different libraries that never agreed on the
  # name: the `pusher` Ruby gem takes `use_tls`, pusher-js <= 6 took `encrypted`,
  # and pusher-js >= 7 takes `force_tls`/`forceTLS`. Specs configure the transport
  # with the Ruby gem's spelling, so reading only `:encrypted` silently ignored
  # `use_tls: false` and defaulted TLS back on. (#85)
  def self.force_tls
    %i[force_tls forceTLS encrypted use_tls].each do |key|
      return opts[key] if opts.key?(key)
    end
    true
  end

  # pusher-js 8 dropped `encrypted` as a TLS switch entirely (there it now means
  # end-to-end encrypted channels), but keep the old name working for anyone
  # reading it.
  singleton_class.send(:alias_method, :encrypted, :force_tls)

  def self.expire_polled_connection_in
    opts[:expire_polled_connection_in] || (5 * 60)
  end

  def self.seconds_between_poll
    opts[:seconds_between_poll] || 0.5
  end

  def self.expire_new_connection_in
    opts[:expire_new_connection_in] || 10.seconds
  end

  def self.refresh_channels_timeout
    opts[:refresh_channels_timeout] || 5.seconds
  end

  def self.refresh_channels_every
    opts[:refresh_channels_every] || 2.minutes
  end

  def self.refresh_channels
    if transport == :action_cable
      Hyperstack::ActionCableChannel.subscriptions.keys.select do |channel|
        Hyperstack::ActionCableChannel.subscriptions[channel] > 0
      end
    else
      new_channels = pusher.channels[:channels].collect do |channel, _etc|
        channel.gsub(/^#{Regexp.quote(Hyperstack.channel)}\-/, '').gsub('==', '::')
      end
    end
  end

  def self.send_data(channel, data)
    if forward_to_server?
      send_to_server(channel, data)
    elsif transport == :pusher
      pusher.trigger("#{Hyperstack.channel}-#{data[1][:channel].gsub('::', '==')}", *data)
    elsif transport == :action_cable
      ActionCable.server.broadcast("hyperstack-#{channel}", { message: data[0], data: data[1] })
    end
  end

  def self.disconnect_channel(channel)
    if transport == :action_cable
      # Remove the channel from the subscriptions hash to mark it as inactive
      Hyperstack::ActionCableChannel.subscriptions.delete(channel)
      # Optionally broadcast a disconnect message to all clients on this channel
      ActionCable.server.broadcast("hyperstack-#{channel}", { message: :disconnect })
    end
  end

  # Is this process the one serving requests?
  #
  # `send_data`, `dispatch` and `ReactiveRecord::Broadcast.after_commit` ask this
  # to choose between broadcasting directly and forwarding to the running server
  # over HTTP (`send_to_server`); the connection adapters' `active` asks it to
  # decide whether this process should be the one expiring and refreshing
  # connections. That is a real distinction and the right question. Until #105 it
  # was asked like this:
  #
  #     def self.on_server?
  #       return defined? Rails::Server
  #     end
  #
  # `Rails::Server` is defined only when the process was started through `rails
  # server`. It is NOT defined under Passenger, a container running `bundle exec
  # puma` or `rackup`, Capybara's in-process server, or any rake task -- so in a
  # normal deployment this answered *false from inside the server itself*, and
  # every broadcast took the forwarding branch: an HTTP POST from the server to
  # itself, landing on `console_update`, which is `raise unless
  # Rails.env.development?` and so answers 401 in production. `send_to_channel`
  # calls `send_data` again on the way back out, so in development the same
  # round trip recurses over HTTP until it times out. #103 (connection tables
  # never created) was one consequence of the same predicate; this is the
  # predicate itself.
  #
  # It is now answered three ways, in order:
  #
  # 1. `Hyperstack.on_server = true/false` -- an explicit statement, for a
  #    deployment shape we cannot recognise, or for a test harness that runs the
  #    server in its own process. `nil` (the default) means "work it out".
  # 2. Whether this process has actually served a request. `Engine`'s middleware
  #    records that on every request, so it is a fact rather than a guess, and it
  #    holds under any rack server. This is the branch that matters: a broadcast
  #    from a controller, a model callback or an ActionCable channel is always
  #    downstream of a request.
  # 3. The boot-time markers of the server processes we can name, for the window
  #    before the first request has been served.
  #
  # Everything else -- a console, a rake task, a background job worker -- answers
  # false and forwards, which is what it wants.
  def self.on_server?
    return on_server unless on_server.nil?
    return true if @serving_requests

    !!(defined?(::Rails::Server) || defined?(::PhusionPassenger))
  end

  # Set from Engine's middleware on every request: this process serves requests.
  # Deliberately not reset -- a process that has served one request is a server
  # for the rest of its life.
  def self.serving_requests!
    @serving_requests = true
  end

  # An explicit answer for `on_server?`, overriding the detection above.
  # nil (the default) leaves it to `on_server?`.
  define_setting(:on_server, nil)

  # Should this broadcast be handed to the running server over HTTP instead of
  # being delivered from here?
  #
  # `send_data`, `dispatch` and `ReactiveRecord::Broadcast.after_commit` all ask
  # this. Until #112 they asked only `!on_server? && Connection.root_path`, which
  # is the wrong axis: whether the *local* branch works is decided by the
  # transport and its adapter, not by which process we happen to be in.
  #
  #   transport / adapter                        deliver from a rake task?
  #   :simple_poller (or :none), AR or redis      yes -- writes the QueuedMessage
  #                                                   rows the client polls out
  #   :pusher                                     yes -- an outbound API call
  #   :action_cable, cable adapter redis/postgres yes -- shared cable backend
  #   :action_cable, cable adapter async/inline   NO  -- the subscriber list is
  #                                                   inside the web process
  #
  # Only the last row needs the hop, and `console_update` -- the route
  # `send_to_server` posts to -- is `raise unless Rails.env.development?`, which
  # is consistent with exactly that row, since `async` is Rails' development
  # default. On the other three rows the old condition sent a production rake
  # task, `rails runner` or Sidekiq worker down a route that answers 401,
  # skipping `Connection.send_to_channel` and so writing no rows at all: the
  # dispatch was dropped, silently, on transports where delivering it here would
  # have worked. (#112, the residue of #105.)
  #
  # `on_server?` stays in the condition -- the server must never forward to
  # itself, whatever the transport -- but it is no longer the whole of it. So
  # does `root_path`: with no server recorded there is nothing to forward to, and
  # queueing locally is both harmless and what the polling transports read, where
  # forwarding would raise 'no server running' out of `send_to_server`. (#105)
  def self.forward_to_server?
    !on_server? && !direct_delivery? && !!Connection.root_path
  end

  # Cable pubsub adapters that keep their subscriber list in the memory of the
  # process that created it, so `ActionCable.server.broadcast` from anywhere else
  # reaches nobody. `async` is Rails' development and test default.
  PROCESS_LOCAL_CABLE_ADAPTERS = %w[async inline test].freeze

  # Can a broadcast issued by *this* process reach the clients?
  def self.direct_delivery?
    return false unless Connection.direct_delivery?
    return true unless transport == :action_cable

    !PROCESS_LOCAL_CABLE_ADAPTERS.include?(action_cable_adapter)
  end

  # The pubsub adapter ActionCable is configured with for this environment, as a
  # string, or nil when it cannot be determined -- in which case `direct_delivery?`
  # assumes a shared backend. Guessing "process-local" instead would send the
  # broadcast to a route that refuses it in production, which is the failure this
  # is here to remove.
  def self.action_cable_adapter
    return nil unless defined?(::ActionCable)

    cable = ::ActionCable.server.config.cable
    return nil if cable.nil? || cable.empty?

    adapter = cable[:adapter] || cable['adapter']
    adapter&.to_s
  rescue StandardError
    nil
  end

  def self.pusher
    unless @pusher
      unless channel_prefix
        self.transport = nil
        raise '******** NO CHANNEL PREFIX SET ***************'
      end
      @pusher = Pusher::Client.new(
        opts || { app_id: app_id, key: key, secret: secret, cluster: cluster }
      )
    end
    @pusher
  end

  def self.channel
    "private-#{channel_prefix}"
  end

  def self.authorization(salt, channel, session_id)
    # Rails 7.2 removed Rails.application.secrets; secret_key_base is the
    # direct replacement (available since Rails 4.1).
    secret_key = Rails.application.secret_key_base
    Digest::SHA1.hexdigest(
      "salt: #{salt}, channel: #{channel}, session_id: #{session_id}, secret_key: #{secret_key}"
    )
  end

  def self.send_to_server(channel, data) # TODO this should work the same/similar to HyperMesh / Models way of sending to console
    salt = SecureRandom.hex
    authorization = authorization(salt, channel, data[1][:broadcast_id])
    raise 'no server running' unless Connection.root_path
    uri = URI("#{Connection.root_path}console_update")
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
    if uri.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    request.body = {
      channel: channel, data: data, salt: salt, authorization: authorization
    }.to_json
    response = Timeout::timeout(Hyperstack.send_to_server_timeout) { http.request(request) }
    # Nothing used to read this. A 401 -- which is what `console_update` answers
    # outside development, and what it answers for any exception raised inside it
    # -- looked exactly like a delivered broadcast, so a dropped dispatch left no
    # trace anywhere. #103 and #105 were both silent for the same kind of reason.
    # (#112)
    unless response.is_a?(Net::HTTPSuccess)
      raise "broadcast on channel #{channel} was refused by #{uri}: "\
            "#{response.code} #{response.message}. The message has NOT been sent. "\
            '(console_update only accepts forwarded broadcasts in development; '\
            'outside development the broadcasting process has to be able to '\
            'deliver directly -- see Hyperstack.direct_delivery?)'
    end
    response
  rescue Timeout::Error
    puts "\n********* FAILED TO RECEIVE RESPONSE FROM SERVER WITHIN #{Hyperstack.send_to_server_timeout} SECONDS. CHANGES WILL NOT BE SYNCED ************\n"
    raise 'no server running'
  end

  def self.dispatch(data)
    if forward_to_server?
      Hyperstack.send_to_server(data[:channel], [:dispatch, data])
    else
      Connection.send_to_channel(data[:channel], [:dispatch, data])
    end
  end

  Connection.transport = self
end
