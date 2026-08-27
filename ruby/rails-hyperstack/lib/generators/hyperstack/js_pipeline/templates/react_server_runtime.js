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
