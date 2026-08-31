// OPT-IN client-side ReactDOMServer (#119).
//
// This exists so `react_runtime.js` does not have to carry it. react-dom/server
// measured 189,490 bytes minified -- 44% of the client bundle -- and it is only
// needed by apps that call Hyperstack::Component::Server.render_to_string or
// .render_to_static_markup FROM THE BROWSER. Most apps never do: prerendering
// happens server-side in V8 via react_server_runtime.js, which is a separate
// entrypoint and unaffected by this file.
//
// To use it, add to app/assets/javascripts/application.js:
//
//     //= require react_dom_server_runtime
//
// (react_runtime itself is NOT in application.js -- the layout loads it with its
// own include tag so browsers can cache it across deploys, #108. This one is a
// require because it is opt-in: sprockets serves only what is asked for.)
//
// Without it, the two Server methods raise a message naming this line rather
// than failing silently -- see hyper-component/lib/hyperstack/component/server.rb.
//
// Note the entry point differs from react_server_runtime.js: that one uses
// "react-dom/server.browser" because it runs in bare V8 with no DOM and needs
// the polyfills loaded first. This one runs in a real browser, so the plain
// "react-dom/server" entry is correct and no polyfill import is needed.
import * as ReactDOMServer from "react-dom/server";

Object.assign(window, { ReactDOMServer });
