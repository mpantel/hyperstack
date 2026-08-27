# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'hyperstack/config/version'
require_relative '../version_selector'

Gem::Specification.new do |spec|
  spec.name          = 'hyperstack-config'
  spec.version       = Hyperstack::Config::VERSION
  spec.authors       = ['Mitch VanDuyn', 'Jan Biedermann']
  spec.email         = ['mitch@catprint.com', 'jan@kursator.com']
  spec.summary       = 'Provides a single point configuration module for hyperstack gems'
  spec.homepage      = 'http://ruby-hyperstack.org'
  spec.metadata      = { 'documentation_uri' => 'https://docs.hyperstack.org/' }
  spec.license       = 'MIT'
  # spec.metadata      = {
  #   "homepage_uri" => 'http://ruby-hyperstack.org',
  #   "source_code_uri" => 'https://github.com/ruby-hyperstack/hyper-component'
  # }

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.executables << 'hyperstack-hotloader'
  spec.require_paths = ['lib']

  spec.add_dependency 'listen', '~> 3.0' # for hot loader
  # spec.add_dependency 'mini_racer', '~> 0.2.6'
  spec.add_dependency 'opal', *Hyperstack.version_selector('OPAL_VERSION', '~> 1.8')
  spec.add_dependency 'opal-browser'  # this is needed everywhere else so its loaded here
  spec.add_dependency 'uglifier'
  spec.add_dependency 'websocket' # for hot loader

  spec.add_development_dependency 'bundler'
  # spec.add_development_dependency 'chromedriver-helper'
  # Opal reaches sprockets through opal-rails by default; a cell that sets
  # OPAL_SPROCKETS_VERSION swaps in opal-sprockets, the only route on Rails 8
  # (opal-rails 2.x is capped at `rails < 7.3`). See supported_versions.yml. (#20)
  if (opal_sprockets = Hyperstack.version_selector('OPAL_SPROCKETS_VERSION')).any?
    spec.add_development_dependency 'opal-sprockets', *opal_sprockets
  else
    spec.add_development_dependency 'opal-rails', *Hyperstack.version_selector('OPAL_RAILS_VERSION', '~> 2.0')
  end
  spec.add_development_dependency 'opal-browser' , '0.3.3'
  spec.add_development_dependency 'pry-rescue'
  spec.add_development_dependency 'pry-stack_explorer'
  spec.add_development_dependency 'puma'# , '<= 5.4.0'
  spec.add_development_dependency 'rails', *Hyperstack.version_selector('RAILS_VERSION', '>= 5.0.0', '< 7.0')
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec', '~> 3.11'  # not '~> 3.11.0': that caps rspec-core at 3.11, which blocks
  # rspec-rails 7+ and so blocks Rails 7 (its FixtureSupport calls the
  # removed fixture_path=). Left as a range so bundler picks per Rails. (#51)
  spec.add_development_dependency 'rspec-rails'# , '~> 6.1.0'
  spec.add_development_dependency 'rubocop' #, '~> 0.51.0'
  spec.add_development_dependency 'sqlite3', *Hyperstack.version_selector('SQLITE3_VERSION', '< 2') # see https://github.com/rails/rails/issues/35153
  spec.add_development_dependency 'timecop', '~> 0.9.0'
  spec.add_development_dependency 'concurrent-ruby', '1.3.4' # not needed after rails 7.1  https://www.devgem.io/posts/resolving-the-activesupport-logger-issue-in-rails-applications-a-step-by-step-guide
end
