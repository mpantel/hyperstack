module Rails
  module Generators
    module JsPipeline
      # The esbuild + jsbundling-rails JavaScript pipeline, as generated for
      # Rails >= 7 (#19/#21). React and ReactDOM are delivered as JS globals
      # from esbuild bundles while Opal stays on sprockets.
      #
      # Counterpart to Webpacker; see `js_pipeline_strategy` for the choice. The
      # two cannot be merged behind a capability check -- they scaffold different
      # applications -- which is why the generator is the one place in the
      # codebase that legitimately forks on version. (#51)
      module Esbuild
        def install_js_pipeline
          insure_yarn_loaded
          add_esbuild_setup
          add_javascript_dependencies
          wire_react_runtime_into_application_js
          add_builds_asset_paths
          cancel_react_source_import
          install_jsbundling_and_mini_racer
        end

      def pipeline_webpack_check
        # esbuild/jsbundling is set up by `hyperstack:install`, not auto-triggered
        # on component generation. No-op (was: detect ::Webpacker and auto-install).
        nil
      end

      def insure_yarn_loaded
        begin
          yarn_version = `yarn --version`
          raise Errno::ENOENT if yarn_version.blank?
        rescue Errno::ENOENT
          raise Thor::Error.new("please install Node.js + the `yarn` command — esbuild builds the React bundles")
        end
      end

      # The esbuild entry points + build config + package.json (mirrors the
      # validated hyper-component reference). IIFE bundles set React globals;
      # Opal stays on sprockets.
      def add_esbuild_setup
        create_file 'app/javascript/react_runtime.js', esbuild_template('react_runtime.js')
        create_file 'app/javascript/react_server_runtime.js', esbuild_template('react_server_runtime.js')
        create_file 'app/javascript/text_encoder_polyfill.js', esbuild_template('text_encoder_polyfill.js')
        create_file 'esbuild.config.js', esbuild_template('esbuild.config.js')
        # let sprockets precompile/serve the esbuild output
        manifest = Rails.root.join('app', 'assets', 'config', 'manifest.js')
        if File.exist?(manifest) && File.readlines(manifest).grep(%r{link_tree \.\./builds}).empty?
          append_file manifest, "//= link_tree ../builds\n", verbose: false
        end
      end

      def add_javascript_dependencies
        unless File.exist?(Rails.root.join('package.json'))
          create_file 'package.json', <<-JSON
{
  "name": "#{File.basename(Rails.root.to_s)}",
  "private": true,
  "scripts": {
    "build": "node esbuild.config.js"
  },
  "dependencies": {
    "create-react-class": "^15.7.0",
    "history": "^4.10.1",
    "react": "#{react_npm_version}",
    "react-dom": "#{react_npm_version}",
    "react-router": "^5.3.4",
    "react-router-dom": "^5.3.4"
  },
  "devDependencies": {
    "esbuild": "^0.23.0"
  }
}
          JSON
        end
        run 'yarn install'
      end

      # //= require react_runtime BEFORE the Opal loader, so window.React exists
      # on every page that loads application.js (incl. the hyper-spec harness,
      # which doesn't use app/views/layouts).
      def wire_react_runtime_into_application_js
        application_js = Rails.root.join('app', 'assets', 'javascripts', 'application.js')
        insure_hyperstack_loader_installed unless File.exist?(application_js)
        return unless File.exist?(application_js)
        return if File.foreach(application_js).any? { |l| l =~ %r{//=\s+require\s+react_runtime} }
        inject_into_file application_js.to_s, verbose: false,
                         before: %r{//=\s+require\s+hyperstack-loader} do
          "//= require react_runtime\n"
        end
      end

      def add_builds_asset_paths
        # `rails new --skip-asset-pipeline` (the Rails 8 route, #20) ships no
        # config/initializers/assets.rb, and append_file on a missing file raises
        # -- aborting the generator mid-run, before app/hyperstack is scaffolded,
        # while still exiting 0. Create it first.
        assets_initializer = 'config/initializers/assets.rb'
        unless File.exist?(File.join(destination_root, assets_initializer))
          create_file assets_initializer,
                      "# Be sure to restart your server when you modify this file.\n",
                      verbose: false
        end
        append_file assets_initializer, verbose: false do
          <<-RUBY
# esbuild output (#19): serve app/assets/builds via sprockets, and put it on the
# Opal load path so the prerender bundle's `require 'react_server_runtime'`
# resolves (Opal's load path is not sprockets' asset path).
Rails.application.config.assets.paths << Rails.root.join('app', 'assets', 'builds').to_s
require 'opal'
Opal.append_path Rails.root.join('app', 'assets', 'builds').to_s
          RUBY
        end
      end
      def install_jsbundling_and_mini_racer
        gem 'jsbundling-rails' unless gem_in_gemfile?('jsbundling-rails')
        gem 'mini_racer'       unless gem_in_gemfile?('mini_racer') # prerendering (V8)
        Bundler.with_unbundled_env { run 'bundle install' }
        run 'spring stop || true'
        # build now; jsbundling-rails also hooks `javascript:build` into assets:precompile
        run 'yarn build'
      end

      # Override the base's no-op (#66). The base only PREPENDS a commented-out
      # line, which documents the option for a fresh app but cancels nothing --
      # so `rails-hyperstack.rb`'s unconditional
      # `js_import 'react/react-source-browser'` still put the react-rails UMD
      # into the Opal loader manifest. application.js requires react_runtime
      # BEFORE hyperstack-loader, so the UMD assigned window.React last and won:
      # the app shipped a 1.2 MB React 19 bundle and then ran React 16.14.
      #
      # Ported from rails-7, where it has always been the real thing. Kept in the
      # esbuild strategy rather than the base because the Webpacker path also
      # calls cancel_react_source_import, and cancelling there is untested on
      # this line -- the three Rails 6.1 cells currently depend on the sprockets
      # React being present.
      #
      # react_server_runtime is loaded at_head in the prerender bundle so its
      # globals are set before the React defines-check runs. cancel_import is a
      # safe no-op when hyper-router isn't present (#32).
      def cancel_react_source_import
        inject_into_initializer(
          "Hyperstack.cancel_import 'react/react-source-browser'\n"\
          "Hyperstack.cancel_import 'react/react-source-server'\n"\
          "Hyperstack.cancel_import 'hyperstack/router/react-router-source'\n"\
          "Hyperstack.import 'react_server_runtime', js_import: true, server_only: true, at_head: true"
        )
      end

      # The npm React the esbuild bundles are built from. Parameterised so a
      # matrix cell can SELECT it, the way REACT_RAILS_VERSION selects the
      # sprockets/react-rails React (#51).
      #
      # Without this the version was hardcoded, so the React axis was selectable
      # on one delivery path and frozen on the other -- which is why no cell could
      # honestly claim React 19: the only lever moved react-rails, and react-rails
      # tops out at 3.3 / React 18.2.
      #
      # Default stays ^19.0.0, so an unparameterised install is unchanged.
      def react_npm_version
        ENV['REACT_NPM_VERSION'] || '^19.0.0'
      end

      # The esbuild scaffolding, verbatim from lib/generators/hyperstack/js_pipeline/templates.
      #
      # These are FILES rather than heredocs because they have a second consumer:
      # ruby/test_app_react_source.rb places the same four files into each gem's
      # spec/test_app when a matrix cell selects HYPERSTACK_REACT_SOURCE=npm (#40).
      # As heredocs the two copies could drift, and the suite would then be proving
      # a runtime we do not actually generate.
      def esbuild_template(name)
        File.read(File.expand_path("templates/#{name}", __dir__), encoding: 'UTF-8')
      end

      def gem_in_gemfile?(name)
        gemfile = Rails.root.join('Gemfile')
        File.exist?(gemfile) &&
          File.foreach(gemfile).any? { |l| l =~ /^\s*gem\s+['"]#{Regexp.escape(name)}['"]/ }
      end

      # --- shared surface used by the add-on framework generators -------------
      # See the Webpacker strategy for why these exist. (#98)

      # esbuild: react_runtime.js is the React bundle's entrypoint and is loaded
      # before the Opal loader, so a global assigned here exists by the time any
      # component renders -- the same guarantee the Webpacker manifest gave.
      def expose_npm_global(global, package)
        append_file 'app/javascript/react_runtime.js', verbose: false do
          "\nimport #{global} from \"#{package}\"; window.#{global} = #{global};\n"
        end
      end

      # The esbuild setup bundles JS only -- there is no scss entrypoint to
      # import into, so take the package's CSS from its CDN instead.
      def add_npm_stylesheet(scss_path:, cdn_url:)
        inject_into_file 'app/views/layouts/application.html.erb', after: /stylesheet_link_tag.*$/ do
          "\n    <link rel=\"stylesheet\" href=\"#{cdn_url}\">\n"
        end
      end

      def build_js_bundle
        run 'yarn build'
      end
      end
    end
  end
end
