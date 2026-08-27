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
