# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'hyperstack/version'
require_relative '../version_selector'

Gem::Specification.new do |spec|
  spec.name        = 'rails-hyperstack'
  spec.version     = Hyperstack::VERSION
  spec.summary     = 'Hyperstack for Rails with generators'
  spec.description = 'This gem provide a full hyperstack for rails plus generators for Hyperstack elements'
  spec.authors     = ['Loic Boutet', 'Adam George', 'Mitch VanDuyn', 'Jan Biedermann']
  spec.email       = ['loic@boutet.com', 'jan@kursator.com']
  spec.homepage    = 'http://hyperstack.org'
  spec.metadata    = { 'documentation_uri' => 'https://docs.hyperstack.org/' }
  spec.license     = 'MIT'
  # spec.metadata = {
  #   "homepage_uri" => 'http://hyperstack.org',
  #   "source_code_uri" => 'https://github.com/hyperstack
  # }
  spec.files       = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(tasks)/}) }
  spec.require_paths = ['lib']
  # post_install_message deliberately removed (#117).
  #
  # rails-hyperstack was the ONLY one of the 11 gemspecs setting this field, and
  # the only one whose upload failed GitLab's server-side metadata extraction --
  # twice, deterministically, each time leaving a `Gem.Temporary.Package` record
  # in `error` status while the deploy job still reported success.
  #
  # The welcome banner is cosmetic; publishing the gem is not. If #117 later
  # identifies a length threshold rather than the field itself, a shortened
  # version can come back.

  spec.add_dependency 'hyper-model', Hyperstack::VERSION
  spec.add_dependency 'hyper-router', Hyperstack::ROUTERVERSION
  spec.add_dependency 'hyperstack-config', Hyperstack::VERSION
  # Opal reaches sprockets through opal-rails by default; a cell that sets
  # OPAL_SPROCKETS_VERSION swaps in opal-sprockets, the only route on Rails 8
  # (opal-rails 2.x is capped at `rails < 7.3`). See supported_versions.yml. (#20)
  if (opal_sprockets = Hyperstack.version_selector('OPAL_SPROCKETS_VERSION')).any?
    spec.add_dependency 'opal-sprockets', *opal_sprockets
  else
    spec.add_dependency 'opal-rails', *Hyperstack.version_selector('OPAL_RAILS_VERSION', '~> 2.0')
  end
  spec.add_dependency 'opal', *Hyperstack.version_selector('OPAL_VERSION', '~> 1.8')
  spec.add_dependency 'react-rails', *Hyperstack.version_selector('REACT_RAILS_VERSION', '>= 2.4.0', '< 4.0')
  # spec.add_dependency 'mini_racer', '~> 0.2.6'
  # spec.add_dependency 'libv8', '~> 7.3.492.27.1'
  spec.add_dependency 'rails', *Hyperstack.version_selector('RAILS_VERSION', '>= 5.0.0', '< 9.0')
  spec.add_development_dependency 'bundler'
  # spec.add_development_dependency 'chromedriver-helper'
  spec.add_development_dependency 'hyper-spec', Hyperstack::VERSION
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'puma'# , '<= 5.4.0'
  spec.add_development_dependency 'bootsnap'
  spec.add_development_dependency 'rspec-rails'# , '~> 6.1.0'
  spec.add_development_dependency 'rubocop' #, '~> 0.51.0'
  spec.add_development_dependency 'sqlite3', *Hyperstack.version_selector('SQLITE3_VERSION', '< 2') # '~> 1.4' # was 1.3.6 -- see https://github.com/rails/rails/issues/35153
  spec.add_development_dependency 'sass-rails', '>= 5.0'
  # Use Uglifier as compressor for JavaScript assets
  spec.add_development_dependency 'uglifier', '>= 1.3.0'
  # See https://github.com/rails/execjs#readme for more supported runtimes
  # gem 'mini_racer', platforms: :ruby

  # Use CoffeeScript for .coffee assets and views
  #spec.add_development_dependency 'coffee-rails', '~> 4.2'
  # Turbolinks makes navigating your web application faster. Read more: https://github.com/turbolinks/turbolinks
  spec.add_development_dependency 'turbolinks', '~> 5'
  # Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
  spec.add_development_dependency 'jbuilder'#, '~> 2.5'
  spec.add_development_dependency 'foreman'
  spec.add_development_dependency 'database_cleaner'
  spec.add_development_dependency 'concurrent-ruby', '1.3.4' # not needed after rails 7.1  https://www.devgem.io/posts/resolving-the-activesupport-logger-issue-in-rails-applications-a-step-by-step-guide

end
