# -*- encoding: utf-8 -*-
$:.push File.expand_path('../lib/', __FILE__)
require 'hyperstack/component/version'

Gem::Specification.new do |spec|
  spec.name          = 'hyper-component'
  spec.version       = Hyperstack::Component::VERSION

  spec.authors       = ['David Chang', 'Adam Jahn', 'Mitch VanDuyn', 'Jan Biedermann', 'Adam Creekroad']
  spec.email         = ['mitch@catprint.com']
  spec.homepage      = 'http://ruby-hyperstack.org'
  spec.metadata      = { 'documentation_uri' => 'https://docs.hyperstack.org/' }
  spec.summary       = 'Opal Ruby wrapper of React.js library.'
  spec.license       = 'MIT'
  spec.description   = 'Write React UI components in pure Ruby.'
  spec.files         = `git ls-files`.split("\n").reject { |f| f.match(%r{^(gemfiles|spec)/}) }
  spec.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  spec.require_paths = ['lib']

  spec.add_dependency 'hyper-state', Hyperstack::Component::VERSION
  spec.add_dependency 'hyperstack-config', Hyperstack::Component::VERSION
  spec.add_dependency 'opal-activesupport', '~> 0.3.3'
  spec.add_dependency 'react-rails', *(ENV['REACT_RAILS_VERSION'] ? [ENV['REACT_RAILS_VERSION']] : ['>= 2.4.0', '< 2.7.0'])

  spec.add_development_dependency 'bundler'
  # spec.add_development_dependency 'chromedriver-helper'
  spec.add_development_dependency 'hyper-spec', Hyperstack::Component::VERSION
  spec.add_development_dependency 'jquery-rails'
  spec.add_development_dependency 'listen'
  spec.add_development_dependency 'mime-types'
  # spec.add_development_dependency 'mini_racer'#, '< 0.8.0' # something is busted with 0.4.0 and its libv8-node dependency
  spec.add_development_dependency 'nokogiri'
  spec.add_development_dependency 'opal-jquery'
  # Opal reaches sprockets through opal-rails by default; a cell that sets
  # OPAL_SPROCKETS_VERSION swaps in opal-sprockets, the only route on Rails 8
  # (opal-rails 2.x is capped at `rails < 7.3`). See supported_versions.yml. (#20)
  # A BLANK selector means unset: '' is truthy in Ruby, and the cell image
  # exposes every unselected ARG as an empty env var, which would otherwise
  # become the requirement "" -> "Illformed requirement". (#78 does this for
  # every selector.)
  if (opal_sprockets_version = ENV['OPAL_SPROCKETS_VERSION'].to_s.strip) != ''
    spec.add_development_dependency 'opal-sprockets', opal_sprockets_version
  else
    spec.add_development_dependency 'opal-rails', *(ENV['OPAL_RAILS_VERSION'] ? [ENV['OPAL_RAILS_VERSION']] : ['~> 2.0'])
  end
  spec.add_development_dependency 'pry-rescue'
  spec.add_development_dependency 'pry-stack_explorer'
  spec.add_development_dependency 'puma'# , '<= 5.4.0'
  spec.add_development_dependency 'rails', *(ENV['RAILS_VERSION'] ? [ENV['RAILS_VERSION']] : ['>= 5.0.0', '< 7.0'])
  spec.add_development_dependency 'rails-controller-testing'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec-rails'# , '~> 6.1.0'
  spec.add_development_dependency 'rubocop' #, '~> 0.51.0'
  spec.add_development_dependency 'sqlite3', (v = ENV['SQLITE3_VERSION'].to_s.strip).empty? ? '< 2' : v
  spec.add_development_dependency 'timecop', '~> 0.9.0'
  spec.add_development_dependency 'concurrent-ruby', '1.3.4' # not needed after rails 7.1  https://www.devgem.io/posts/resolving-the-activesupport-logger-issue-in-rails-applications-a-step-by-step-guide

end
