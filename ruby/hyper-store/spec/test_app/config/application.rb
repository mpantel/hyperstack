require 'rails/all'
require File.expand_path('../boot', __FILE__)

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups(assets: %w(development test)))

# opal-rails on Rails < 7.3, opal-sprockets on Rails 8 (opal-rails 2.x is
# capped at `rails < 7.3`). Either one registers the sprockets Opal processor;
# the Rails wiring opal-rails' engine adds is in hyperstack/rail_tie. (#20)
begin
  require 'opal-rails'
rescue LoadError
  require 'opal-sprockets'
end
#require 'hyper-react'

module TestApp
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.
    # config.opal.arity_check = false
  end
end
