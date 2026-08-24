require 'hyperstack/internal/component'

Hyperstack.js_import 'react/react-source-browser', client_only: true, defines: %w[ReactDOM React]
Hyperstack.js_import 'react/react-source-server', server_only: true, defines: 'React'
Hyperstack.import    'browser/delay', client_only: true
Hyperstack.import    'browser/interval', client_only: true
Hyperstack.js_import 'react_ujs', defines: 'ReactRailsUJS'
Hyperstack.import    'hyper-component'  # TODO: confirm this does not break anything.  Added while converting hyperloop->hyperstack
Hyperstack.import    'hyperstack/component/auto-import'  # TODO: confirm we can cancel the import

if RUBY_ENGINE == 'opal'
  require 'hyperstack/internal/callbacks'
  require 'hyperstack/internal/auto_unmount'
  require 'native'
  require 'hyperstack/internal/component/native_to_hash'
  require 'json'
  require 'hyperstack/state/observer'
  require 'hyperstack/internal/component/validator'
  require 'hyperstack/component/element'
  require 'hyperstack/internal/component/react_wrapper'
  require 'hyperstack/component'
  require 'hyperstack/internal/component/should_component_update'
  require 'hyperstack/internal/component/tags'
  require 'hyperstack/component/event'
  require 'hyperstack/internal/component/rendering_context'
  require 'hyperstack/ext/component/object'
  require 'hyperstack/ext/component/kernel'
  require 'hyperstack/ext/component/number'
  require 'hyperstack/ext/component/boolean'
  require 'hyperstack/ext/component/array'
  require 'hyperstack/ext/component/enumerable'
  require 'hyperstack/ext/component/time'
  require 'hyperstack/component/isomorphic_helpers'
  require 'hyperstack/component/react_api'
  require 'hyperstack/internal/component/top_level_rails_component'
  require 'hyperstack/component/while_loading'
  require 'hyperstack/component/free_render'
  require 'hyperstack/internal/component/rescue_wrapper'
  require 'hyperstack/internal/component/while_loading_wrapper'

  require 'hyperstack/component/version'

  # React 18/19 (#39): on the sprockets path (react/react-source-browser UMD),
  # react-rails' react_ujs and Hyperstack's own mount path (react_api.rb) call the
  # top-level `ReactDOM.createRoot`. React 18+ logs a benign console.error
  # deprecation on every access ("You are importing createRoot from react-dom
  # which is not supported. You should instead import it from react-dom/client"),
  # but the UMD bundle exposes no separate `react-dom/client` global to import
  # from — the top-level entry is the only one available, so the warning is
  # unavoidable on this path (the esbuild build avoids it by exposing
  # react-dom/client's createRoot as window.ReactDOM.createRoot). Drop just that
  # one message client-side so it does not masquerade as a real error — e.g. specs
  # that assert on the count of SEVERE console errors. Installed once.
  %x{
    if (typeof console !== 'undefined' && console.error && !console.error.__hyperstackCreateRootFilter) {
      var __hyperstackOrigConsoleError = console.error;
      var __hyperstackFilteredError = function() {
        var msg = arguments[0];
        if (typeof msg === 'string' &&
            msg.indexOf('which is not supported. You should instead import it from') !== -1 &&
            (msg.indexOf('createRoot') !== -1 || msg.indexOf('hydrateRoot') !== -1)) {
          return;
        }
        return __hyperstackOrigConsoleError.apply(console, arguments);
      };
      __hyperstackFilteredError.__hyperstackCreateRootFilter = true;
      console.error = __hyperstackFilteredError;
    }
  }
else
  require 'opal'
  require 'hyper-state'
  require 'opal-activesupport'
  require 'hyperstack/component/version'
  require 'hyperstack/internal/component/rails'
  require 'hyperstack/component/isomorphic_helpers'
  require 'hyperstack/ext/component/serializers'

  Opal.append_path File.expand_path('../', __FILE__)
  require 'react/react-source'
end
