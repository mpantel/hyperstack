# coding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'hyperstack/i18n/version'

Gem::Specification.new do |spec|
  spec.name          = 'hyper-i18n'
  spec.version       = Hyperstack::I18n::VERSION
  spec.authors       = ['adamcreekroad']
  spec.email         = ['adamgeorge.31@gmail.com']

  spec.summary       = 'HyperI18n seamlessly brings Rails I18n into your Hyperstack application.'
  spec.homepage      = 'http://ruby-hyperstack.org'
  spec.metadata      = { 'documentation_uri' => 'https://docs.hyperstack.org/' }
  spec.license       = 'MIT'

  spec.files          = `git ls-files`.split("\n")
  spec.executables    = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  spec.test_files     = `git ls-files -- {test,spec,features}/*`.split("\n")
  spec.require_paths  = ['lib']

  spec.add_dependency 'hyper-operation', Hyperstack::I18n::VERSION
  spec.add_dependency 'i18n'

  spec.add_development_dependency 'rails', *(ENV['RAILS_VERSION'] ? [ENV['RAILS_VERSION']] : ['>= 5.0.0', '< 7.0'])
  spec.add_development_dependency 'bundler'
  # spec.add_development_dependency 'chromedriver-helper'
  spec.add_development_dependency 'hyper-model', Hyperstack::I18n::VERSION
  spec.add_development_dependency 'hyper-spec', Hyperstack::I18n::VERSION
  # spec.add_development_dependency 'mini_racer' # , '< 0.8.0' # something is busted with 0.4.0 and its libv8-node dependency
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
  spec.add_development_dependency 'pry'
  spec.add_development_dependency 'puma'# , '<= 5.4.0'
  spec.add_development_dependency 'rake'#, '~> 10.0'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rspec-rails'# , '~> 6.1.0'
  spec.add_development_dependency 'rubocop' #, '~> 0.51.0'
  spec.add_development_dependency 'sqlite3', (v = ENV['SQLITE3_VERSION'].to_s.strip).empty? ? '< 2' : v # see https://github.com/rails/rails/issues/35153
  spec.add_development_dependency 'concurrent-ruby', '1.3.4' # not needed after rails 7.1  https://www.devgem.io/posts/resolving-the-activesupport-logger-issue-in-rails-applications-a-step-by-step-guide

end
