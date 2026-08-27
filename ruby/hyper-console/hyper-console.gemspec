# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'hyperloop/console/version'
require_relative '../version_selector'

Gem::Specification.new do |spec|
  spec.name          = "hyper-console"
  spec.version       = Hyperloop::Console::VERSION
  spec.authors       = ["catmando"]
  spec.email         = ["mitch@catprint.com"]

  spec.summary       = %q{IRB style console for Hyperloop applications.}
  spec.homepage      = "http://ruby-hyperloop.io"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'hyper-operation', Hyperloop::Console::VERSION
  spec.add_dependency 'hyper-store', Hyperloop::Console::VERSION

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'chromedriver-helper'
  spec.add_development_dependency 'hyper-component', Hyperloop::Console::VERSION
  spec.add_development_dependency 'hyper-operation', Hyperloop::Console::VERSION
  spec.add_development_dependency 'hyper-store', Hyperloop::Console::VERSION
  spec.add_development_dependency 'hyperstack-config', Hyperloop::Console::VERSION
  spec.add_development_dependency 'opal', *Hyperstack.version_selector('OPAL_VERSION', '~> 1.8')
  spec.add_development_dependency 'opal-browser'
  spec.add_development_dependency 'opal-jquery'
  # Opal reaches sprockets through opal-rails by default; a cell that sets
  # OPAL_SPROCKETS_VERSION swaps in opal-sprockets, the only route on Rails 8
  # (opal-rails 2.x is capped at `rails < 7.3`). See supported_versions.yml. (#20)
  if (opal_sprockets = Hyperstack.version_selector('OPAL_SPROCKETS_VERSION')).any?
    spec.add_development_dependency 'opal-sprockets', *opal_sprockets
  else
    spec.add_development_dependency 'opal-rails', *Hyperstack.version_selector('OPAL_RAILS_VERSION', '~> 2.0')
  end
  spec.add_development_dependency 'rails', *Hyperstack.version_selector('RAILS_VERSION', '>= 5.0.0', '< 7.0')
  spec.add_development_dependency 'rake'#, '~> 10.0'
  spec.add_development_dependency 'uglifier'#, '4.1.6'
end
