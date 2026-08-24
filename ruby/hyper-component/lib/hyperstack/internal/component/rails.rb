if defined?(Rails)
  require 'action_view'
  require 'react-rails'
  # #29 connection_pool shim removed: react-rails 3.3+ builds its server-rendering
  # pool with keyword args natively (`ConnectionPool.new(**options)`), so the
  # positional-hash workaround for react-rails 2.7.1 is no longer needed.
  require 'hyperstack/internal/component/rails'
  require 'hyperstack/internal/component/rails/server_rendering/hyper_asset_container'
  require 'hyperstack/internal/component/rails/server_rendering/contextual_renderer'
  require 'hyperstack/internal/component/rails/component_mount'
  require 'hyperstack/internal/component/rails/railtie'
  require 'hyperstack/internal/component/rails/controller_helper'
  require 'hyperstack/internal/component/rails/component_loader'
end
