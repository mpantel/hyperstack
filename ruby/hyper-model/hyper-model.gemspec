# -*- encoding: utf-8 -*-
$:.push File.expand_path('../lib/', __FILE__)
require 'hyper_model/version'
require_relative '../version_selector'

Gem::Specification.new do |spec|
  spec.name          = 'hyper-model'
  spec.version       = HyperModel::VERSION
  spec.authors       = ['Mitch VanDuyn', 'Jan Biedermann']
  spec.email         = ['mitch@catprint.com', 'jan@kursator.com']
  spec.summary       = 'React based CRUD access and Synchronization of active record models across multiple clients'
  spec.description   = 'HyperModel gives your HyperComponents CRUD access to your '\
                       'ActiveRecord models on the client, using the the standard ActiveRecord '\
                       'API. HyperModel also implements push notifications (via a number of '\
                       'possible technologies) so changes to records on the server are '\
                       'dynamically updated on all authorised clients.'
  spec.homepage      = 'http://ruby-hyperstack.org'
  spec.metadata      = { 'documentation_uri' => 'https://docs.hyperstack.org/' }
  spec.license       = 'MIT'
  spec.files          = `git ls-files`.split("\n").reject { |f| f.match(%r{^(examples|gemfiles|pkg|reactive_record_test_app|spec)/}) }
  # spec.executables    = `git ls-files -- bin/*`.split("\n").map { |f| File.basename(f) }
  spec.test_files     = `git ls-files -- {spec}/*`.split("\n")
  spec.require_paths  = ['lib']

  spec.add_dependency 'activemodel'
  spec.add_dependency 'activerecord', '>= 4.0.0'
  spec.add_dependency 'hyper-operation', HyperModel::VERSION

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'database_cleaner'
  spec.add_development_dependency 'factory_bot_rails'
  spec.add_development_dependency 'hyper-spec', HyperModel::VERSION
  spec.add_development_dependency 'hyper-trace', HyperModel::VERSION
  # spec.add_development_dependency 'mini_racer'#, '< 0.8.0' # something is busted with 0.4.0 and its libv8-node dependency
  # pg drives the database the specs actually run against, and was unpinned: a
  # new major could arrive here with no commit of ours -- and it would arrive
  # on cells running EOL Rails 6.1, whose postgresql_adapter calls
  # PG::Coder.new with a positional Hash -- deprecated in pg since 1.5.0, fixed
  # in Rails 7.2+ and never in 6.1 -- so a major that finishes that deprecation
  # turns a warning into a failure. Cap the major; a cell moves it with
  # PG_VERSION, the way SQLITE3_VERSION is moved. (#102)
  spec.add_development_dependency 'pg', *Hyperstack.version_selector('PG_VERSION', '< 2')
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
  spec.add_development_dependency 'pusher'
  spec.add_development_dependency 'pusher-fake'
  spec.add_development_dependency 'rails', *Hyperstack.version_selector('RAILS_VERSION', '>= 5.0.0', '< 9.0')
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'react-rails', *Hyperstack.version_selector('REACT_RAILS_VERSION', '>= 2.4.0', '< 4.0')
  spec.add_development_dependency 'rspec-collection_matchers'
  spec.add_development_dependency 'rspec-expectations'
  spec.add_development_dependency 'rspec-its'
  spec.add_development_dependency 'rspec-mocks'
  spec.add_development_dependency 'rspec-rails'# , '~> 6.1.0'
  spec.add_development_dependency 'rspec-steps', '~> 2.1.1'
  spec.add_development_dependency 'rspec-wait'
  spec.add_development_dependency 'rubocop' #, '~> 0.51.0'
  spec.add_development_dependency 'shoulda'
  spec.add_development_dependency 'shoulda-matchers'
  spec.add_development_dependency 'spring-commands-rspec', '~> 1.0.4'
  spec.add_development_dependency 'sqlite3', *Hyperstack.version_selector('SQLITE3_VERSION', '< 2') # see https://github.com/rails/rails/issues/35153, '~> 1.3.6'
  spec.add_development_dependency 'timecop', '~> 0.9.0'
  spec.add_development_dependency 'concurrent-ruby', '1.3.4' # not needed after rails 7.1  https://www.devgem.io/posts/resolving-the-activesupport-logger-issue-in-rails-applications-a-step-by-step-guide

end
