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
        create_file 'app/javascript/react_runtime.js', <<-'JAVASCRIPT'
// Client React runtime (esbuild -> app/assets/builds, #19). Hyperstack's Opal
// code reads React/ReactDOM/etc. as JS globals, so bundle them and hoist to
// window. Opal stays on sprockets (//= require hyperstack-loader).
import React from "react";
import ReactDOM from "react-dom";
import * as ReactDOMClient from "react-dom/client";
import * as ReactDOMServer from "react-dom/server";
import createReactClass from "create-react-class";
import * as History from "history";
import * as ReactRouter from "react-router";
import * as ReactRouterDOM from "react-router-dom";

// React 18+ (#18/#19): ReactDOM.render/unmountComponentAtNode are gone; the
// replacement createRoot/hydrateRoot live in the react-dom/client entry. In
// React 18 they ALSO appear on react-dom but warn unless the call routes through
// the client entry; in React 19 they're removed from react-dom entirely (only
// flushSync remains on the top-level). Import them from react-dom/client and
// expose them on ReactDOM so both consumers that read window.ReactDOM.createRoot
// — Hyperstack's mount path AND react-rails' react_ujs — get the warning-free
// client implementation on every React >= 18, with no internals/flag hack.
//
// Cache one root per container (keyed by `__hyperstackReactRoot`, the same key
// Hyperstack's mount/unmount uses): React errors ("already passed to createRoot")
// if createRoot is called twice on the same node, which happens when both
// react-rails' react_ujs.mountComponents AND Hyperstack's mount path target it.
// Unmount deletes the key, so a fresh root is created after unmount.
ReactDOM.createRoot = function (container, options) {
  if (container && container.__hyperstackReactRoot) { return container.__hyperstackReactRoot; }
  var root = ReactDOMClient.createRoot(container, options);
  if (container) { container.__hyperstackReactRoot = root; }
  return root;
};
ReactDOM.hydrateRoot = ReactDOMClient.hydrateRoot;

Object.assign(window, {
  React, ReactDOM, ReactDOMServer, createReactClass, History, ReactRouter, ReactRouterDOM
});
// add additional npm packages here, e.g.:  import Foo from "foo"; window.Foo = Foo;
        JAVASCRIPT
        create_file 'app/javascript/react_server_runtime.js', <<-'JAVASCRIPT'
// Server/prerender React runtime (esbuild). Runs in mini_racer/V8 which has no
// window, so set globals on the object Opal resolves at boot (Opal.global), and
// use react-dom/server.browser (string renderToString, no Node streams). #19/#6.
// MUST be first: react-dom/server.browser references platform APIs at module
// load that bare V8 lacks — a TextEncoder (React 18) and a MessageChannel
// (React 19 scheduler). ES imports evaluate in source order, so this installs
// the polyfills before the React import below runs. (#18/#19)
import "./text_encoder_polyfill";
import React from "react";
import ReactDOMServer from "react-dom/server.browser";
import createReactClass from "create-react-class";
import * as History from "history";
import * as ReactRouter from "react-router";
import * as ReactRouterDOM from "react-router-dom";

var g = (typeof Opal !== "undefined" && Opal.global) ? Opal.global : globalThis;
Object.assign(g, {
  React, ReactDOMServer, createReactClass, History, ReactRouter, ReactRouterDOM
});
        JAVASCRIPT
        create_file 'app/javascript/text_encoder_polyfill.js', <<-'JAVASCRIPT'
// React SSR (#18/#19): react-dom/server.browser references Web/Node platform
// APIs at module-load time that the prerender bundle's mini_racer/V8 isolate
// (bare V8) lacks — TextEncoder/TextDecoder (React 18) and MessageChannel
// (React 19 scheduler) — so the import throws `ReferenceError: <API> is not
// defined`. Imported first in react_server_runtime.js so these are installed
// before React's module body runs. TextEncoder/TextDecoder are UTF-8 only; each
// polyfill is guarded, so it is a no-op where the platform already provides it.
if (typeof globalThis.TextEncoder === "undefined") {
  globalThis.TextEncoder = class TextEncoder {
    get encoding() { return "utf-8"; }
    encode(input) {
      var str = String(input === undefined ? "" : input);
      var bytes = [];
      for (var i = 0; i < str.length; i++) {
        var c = str.charCodeAt(i);
        if (c < 0x80) {
          bytes.push(c);
        } else if (c < 0x800) {
          bytes.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
        } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length) {
          var c2 = str.charCodeAt(i + 1);
          if (c2 >= 0xdc00 && c2 <= 0xdfff) {
            c = 0x10000 + ((c & 0x3ff) << 10) + (c2 & 0x3ff);
            i++;
            bytes.push(
              0xf0 | (c >> 18),
              0x80 | ((c >> 12) & 0x3f),
              0x80 | ((c >> 6) & 0x3f),
              0x80 | (c & 0x3f)
            );
          } else {
            bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
          }
        } else {
          bytes.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
        }
      }
      return new Uint8Array(bytes);
    }
  };
}

if (typeof globalThis.TextDecoder === "undefined") {
  globalThis.TextDecoder = class TextDecoder {
    get encoding() { return "utf-8"; }
    decode(input) {
      if (input == null) return "";
      var bytes = input instanceof Uint8Array ? input : new Uint8Array(input.buffer || input);
      var str = "";
      var i = 0;
      while (i < bytes.length) {
        var c = bytes[i++];
        if (c < 0x80) {
          str += String.fromCharCode(c);
        } else if (c < 0xe0) {
          str += String.fromCharCode(((c & 0x1f) << 6) | (bytes[i++] & 0x3f));
        } else if (c < 0xf0) {
          str += String.fromCharCode(
            ((c & 0x0f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f)
          );
        } else {
          var cp =
            ((c & 0x07) << 18) |
            ((bytes[i++] & 0x3f) << 12) |
            ((bytes[i++] & 0x3f) << 6) |
            (bytes[i++] & 0x3f);
          cp -= 0x10000;
          str += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
        }
      }
      return str;
    }
  };
}

// React 19 (#19): react-dom/server's scheduler instantiates a MessageChannel at
// module-load time to schedule async work. The synchronous string renderers
// (renderToString/renderToStaticMarkup) complete within the call and never pump
// the channel, so a no-op port pair is sufficient — it only has to exist so the
// module body doesn't throw `MessageChannel is not defined` in the bare V8
// isolate. (A real browser already provides MessageChannel, so this is guarded.)
if (typeof globalThis.MessageChannel === "undefined") {
  var noop = function () {};
  var makePort = function () {
    return {
      onmessage: null,
      postMessage: noop,
      addEventListener: noop,
      removeEventListener: noop,
      start: noop,
      close: noop,
    };
  };
  globalThis.MessageChannel = class MessageChannel {
    constructor() {
      this.port1 = makePort();
      this.port2 = makePort();
    }
  };
}
        JAVASCRIPT
        create_file 'esbuild.config.js', <<-'JAVASCRIPT'
// esbuild build (#19). IIFE format (not esm) so the bundles set the window /
// Opal.global React globals immediately. Output -> app/assets/builds (served by
// sprockets). jsbundling-rails runs this via the package.json "build" script.
require('esbuild').build({
  entryPoints: [
    'app/javascript/react_runtime.js',        // client: window globals
    'app/javascript/react_server_runtime.js', // prerender (V8): Opal.global globals
  ],
  bundle: true,
  outdir: 'app/assets/builds',
  define: { 'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV || 'production') },
  logLevel: 'info',
}).catch(() => process.exit(1));
        JAVASCRIPT
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
        append_file 'config/initializers/assets.rb', verbose: false do
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

      def gem_in_gemfile?(name)
        gemfile = Rails.root.join('Gemfile')
        File.exist?(gemfile) &&
          File.foreach(gemfile).any? { |l| l =~ /^\s*gem\s+['"]#{Regexp.escape(name)}['"]/ }
      end
      end
    end
  end
end
