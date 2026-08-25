module Rails
  module Generators
    module JsPipeline
      # The Webpacker JavaScript pipeline, as generated for Rails < 7.
      #
      # Split out of InstallGeneratorBase because this is the one part of the
      # generator that genuinely forks by version rather than by a capability
      # check: a Rails 6 app is scaffolded with Webpacker and a Rails 7 app with
      # esbuild + jsbundling-rails. They are different products, not two ways of
      # writing the same thing, so `rails webpacker:install` simply does not
      # exist on Rails 7 ("Unrecognized command"). See Esbuild for the other
      # strategy and `js_pipeline_strategy` for how one is chosen. (#51)
      module Webpacker
        def install_js_pipeline
          insure_yarn_loaded
          add_webpacker_manifests
          add_webpacks
          cancel_react_source_import
          install_webpacker
        end

      def pipeline_webpack_check
        return unless defined? ::Webpacker

        client_and_server = Rails.root.join("app", "javascript", "packs", "client_only.js")
        return if File.exist? client_and_server

        # Dir.chdir(Rails.root.join.to_s) { run 'bundle exec rails hyperstack:install:webpack' }

        # say "warning: you are running webpacker, but the hyperstack webpack files have not been created.\n"\
        #     "         Suggest you run bundle exec rails hyperstack:install:webpack soon.\n"\
        #     "         Or to avoid this warning create an empty file named app/javascript/packs/client_only.js",
        #     :red
        install_webpack
        true
      end

      def insure_yarn_loaded
        begin
          yarn_version = `yarn --version`
          raise Errno::ENOENT if yarn_version.blank?
        rescue Errno::ENOENT
          raise Thor::Error.new("please insure nodejs is installed and the yarn command is available if using webpacker")
        end
      end

      def add_webpacker_manifests
        create_file 'app/javascript/packs/client_and_server.js', <<-JAVASCRIPT
//app/javascript/packs/client_and_server.js
// these packages will be loaded both during prerendering and on the client
React = require('react');                         // react-js library
createReactClass = require('create-react-class'); // backwards compatibility with ECMA5
History = require('history');                     // react-router history library
ReactRouter = require('react-router');            // react-router js library
ReactRouterDOM = require('react-router-dom');     // react-router DOM interface
ReactRailsUJS = require('react_ujs');             // interface to react-rails
// to add additional NPM packages run `yarn add package-name@version`
// then add the require here.
        JAVASCRIPT
        create_file 'app/javascript/packs/client_only.js', <<-JAVASCRIPT
//app/javascript/packs/client_only.js
// add any requires for packages that will run client side only
ReactDOM = require('react-dom');               // react-js client side code
jQuery = require('jquery');                    // remove if you don't need jQuery
// to add additional NPM packages call run yarn add package-name@version
// then add the require here.
        JAVASCRIPT
        append_file 'config/initializers/assets.rb', verbose: false do
          <<-RUBY
  Rails.application.config.assets.paths << Rails.root.join('public', 'packs', 'js').to_s
          RUBY
        end
        inject_into_file 'config/environments/test.rb', verbose: false, before: /^end/ do
          <<-RUBY

  # added by hyperstack installer
  config.assets.paths << Rails.root.join('public', 'packs-test', 'js').to_s
          RUBY
        end
      end

      def add_webpacks
        yarn 'react', '16'
        yarn 'react-dom', '16'
        yarn 'react-router', '^5.0.0'
        yarn 'react-router-dom', '^5.0.0'
        yarn 'react_ujs', '^2.5.0'
        yarn 'jquery', '^3.4.1'
        yarn 'create-react-class'
        yarn '@babel/plugin-proposal-private-methods', '^7.18.6'
        yarn '@babel/plugin-proposal-private-property-in-object', '^7.21.11'

      end

      def install_webpacker
        return if defined?(::Webpacker)

        gem "webpacker"
        Bundler.with_unbundled_env do
          run "bundle install"
        end
        `spring stop`
        Dir.chdir(Rails.root.join.to_s) { run 'bundle exec rails webpacker:install' }
      end
      end
    end
  end
end
