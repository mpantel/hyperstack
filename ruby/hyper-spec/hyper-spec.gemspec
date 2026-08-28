# coding: utf-8
lib = File.expand_path('../lib/', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'hyper-spec/version'
require_relative '../version_selector'

Gem::Specification.new do |spec| # rubocop:disable Metrics/BlockLength
  spec.name          = 'hyper-spec'
  spec.version       = HyperSpec::VERSION
  spec.authors       = ['Mitch VanDuyn', 'AdamCreekroad', 'Jan Biedermann']
  spec.email         = ['mitch@catprint.com', 'jan@kursator.com']
  spec.summary       = 'Drive your Opal and Hyperstack client and server specs from RSpec and Capybara'
  spec.description   = 'A Hyperstack application consists of isomorphic React Components, '\
                       'Active Record Models, Stores, Operations and Policiespec. '\
                       'Test them all from Rspec, regardless if the code runs on the client or server.'
  spec.homepage      = 'http://ruby-hyperstack.org'
  spec.metadata      = { 'documentation_uri' => 'https://docs.hyperstack.org/' }
  spec.license       = 'MIT'
  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(gemfiles|spec)/}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'actionview'
  spec.add_dependency 'capybara'
  # spec.add_dependency 'chromedriver-helper', '1.2.0'
  spec.add_dependency 'filecache'
  spec.add_dependency 'method_source'
  spec.add_dependency 'opal', *Hyperstack.version_selector('OPAL_VERSION', '~> 1.8')
  spec.add_dependency 'parser'
  spec.add_dependency 'prism'
  spec.add_dependency 'rspec'
  spec.add_dependency 'rspec-retry'
  # Pinned to a minor series, not left to float. This is the gem that drives the
  # browser for EVERY js spec in every gem, so an unannounced minor bump changes
  # what the whole suite runs against, between two pipelines on the same commit
  # -- which is exactly what happened: 4.47.0 on 27 Aug 13:44, 4.48.0 at 20:49.
  # A red pipeline should mean the code changed, not that a dependency did. The
  # `.0` matters: `~> 4.48` would allow 4.49 and float again. (#84)
  spec.add_dependency 'selenium-webdriver', '~> 4.48.0'
  spec.add_dependency 'timecop', '~> 0.9.0'
  spec.add_dependency 'uglifier'
  spec.add_dependency 'unparser', '>= 0.4.2'
  # spec.add_dependency 'webdrivers'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'hyper-component', HyperSpec::VERSION
  # spec.add_development_dependency 'mini_racer'#, '< 0.8.0' # something is busted with 0.4.0 and its libv8-node dependency
  # Opal reaches sprockets through opal-rails by default; a cell that sets
  # OPAL_SPROCKETS_VERSION swaps in opal-sprockets, the only route on Rails 8
  # (opal-rails 2.x is capped at `rails < 7.3`). See supported_versions.yml. (#20)
  if (opal_sprockets = Hyperstack.version_selector('OPAL_SPROCKETS_VERSION')).any?
    spec.add_development_dependency 'opal-sprockets', *opal_sprockets
  else
    spec.add_development_dependency 'opal-rails', *Hyperstack.version_selector('OPAL_RAILS_VERSION', '~> 2.0')
  end
  spec.add_development_dependency 'pry-rescue'
  spec.add_development_dependency 'pry-stack_explorer'
  spec.add_development_dependency 'puma'# , '<= 5.4.0'
  spec.add_development_dependency 'rails', *Hyperstack.version_selector('RAILS_VERSION', '>= 5.0.0', '< 9.0')
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'react-rails', *Hyperstack.version_selector('REACT_RAILS_VERSION', '>= 2.3.0', '< 4.0')
  spec.add_development_dependency 'rspec-rails'# , '~> 6.1.0'
  spec.add_development_dependency 'rspec-collection_matchers'
  spec.add_development_dependency 'rspec-expectations'
  spec.add_development_dependency 'rspec-its'
  spec.add_development_dependency 'rspec-mocks'
  spec.add_development_dependency 'rspec-steps', '~> 2.1.1'
  spec.add_development_dependency 'rubocop' #, '~> 0.51.0'
  spec.add_development_dependency 'shoulda'
  spec.add_development_dependency 'shoulda-matchers'
  spec.add_development_dependency 'spring-commands-rspec'
  spec.add_development_dependency 'concurrent-ruby', '1.3.4' # not needed after rails 7.1  https://www.devgem.io/posts/resolving-the-activesupport-logger-issue-in-rails-applications-a-step-by-step-guide

end
