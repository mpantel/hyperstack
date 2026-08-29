# Changelog — the retired Rails 7 and Rails 8 branch lines

Until `1.0.alpha1.9` this project maintained `rails-7`, `rails-8.0` and
`rails-8.1` as separate release lines, each a stacked rebase on `edge` publishing
its own gem set for one Rails version. Their versions encoded the configuration
they were built for — `1.0.alpha1.8.34.18.72.1902.4` is Ruby 3.4 / Opal 1.8 /
Rails 7.2 / React 19.2, patch 4.

Those lines are retired. `edge` now serves all of them from a single gem set
tested across the matrix in [`supported_versions.yml`](./supported_versions.yml),
and the consolidation is described in the `1.0.alpha1.9` entry of the main
[`CHANGELOG.md`](./CHANGELOG.md).

This file preserves the release notes those lines published, which never appeared
in the main changelog. Everything here shipped; nothing here is pending. Where a
fix listed below also exists on `edge` it may have been reimplemented differently
— the `#81` / `#92` / `#93` columns-hash serialization work is the notable case,
where `edge`'s approach supersedes the `rails-8.1` monkey-patch described here.

Entries below the Rails 6.1 versions they branched from are in
[`CHANGELOG.md`](./CHANGELOG.md).

---

## The Rails 8 line (`rails-8.0` / `rails-8.1`)

## 1.0.alpha1.8.40.18.80.1902.0 — 2026-07-02

Rails 8.0 (#20) and Ruby 4.0 (#15). This is the **Rails 8.0** line; the Rails 8.1
line continues on `rails-8.1`, which stacks the 8.1-only changes on top of this
one. App-facing upgrade notes: [`upgrade-from-rails-7-to-8.md`](./upgrade-from-rails-7-to-8.md).

### Bug fixes (React 18/19, #39)

- **React 18/19: restore `rescues`/`WhileLoading` recovery for non-idempotent
  render errors (#39).** On React ≥ 18 (`createRoot`, concurrent renderer), a
  render error whose condition is consumed on the first raise (a transient error,
  or the common `raise_error!` + reset idiom) silently stopped triggering its
  `rescues` block — the fallback never rendered. React 17's legacy root unwound a
  render throw **straight** to the nearest error boundary; React ≥ 18 first tries
  to *recover* by re-rendering the whole root once (`Minified React error #520`)
  and only escalates to `componentDidCatch` if that recovery render **also**
  throws. Because the error trigger was already cleared, the recovery render
  succeeded and the boundary never fired. (`flushSync` does not help — `createRoot`
  always renders through the concurrent reconciler.) `_render_wrapper`
  (`hyper-component .../component.rb`) now catches `StandardError` from render,
  stashes it, and re-raises it on **every** subsequent render so the recovery
  re-render(s) also throw and React escalates to the boundary, restoring the
  React-17 contract. The error persists until the boundary actually handles it
  (`RescueWrapper#after_error` clears it before `force_update!`) rather than for a
  fixed number of retries — React's **development** build additionally re-invokes
  a throwing render to replay the error, so the number of re-renders before the
  boundary fires is not fixed (1 in production, 2+ in development). `NotQuiet`
  (the WhileLoading "waiting on resources" signal — `< Exception`, not
  `StandardError`, and idempotent) is left to propagate on its own, which is why
  plain while-loading already worked; only the non-idempotent explicit-`rescues`
  path regressed. Validated on the react-rails React 18.2 **development** build
  (matching CI): `while_loading_spec` 7/0 (incl. "while loading works along side
  rescues") + a new hyper-component non-idempotent-rescue regression case on the
  React 19.2 esbuild build. Related: #28 (flushSync/batching), #38 (Rails 8
  client-runtime).

- **React 18/19: silence the benign top-level-`createRoot` deprecation on the
  sprockets path so it stops failing SEVERE-error assertions (#39).** On the
  sprockets path (`react/react-source-browser` UMD), react-rails' `react_ujs` and
  Hyperstack's own mount path both call the top-level `ReactDOM.createRoot`; React
  18+ logs a `console.error` deprecation on every access ("importing createRoot
  from react-dom … not supported … import it from react-dom/client"). The UMD
  bundle exposes no separate `react-dom/client` global to import from, so on this
  path the warning is unavoidable (the esbuild build avoids it by exposing
  react-dom/client's createRoot). It is harmless but is logged at **SEVERE**,
  which broke specs that assert on the *count* of console errors
  (`hyper-model server_method_spec` "will allow remote access to methods", which
  expects exactly the two 403s). `hyper-component` now drops **just that one
  message** client-side (installed once, in the Opal-only boot block), and
  `server_method_spec` also filters it from its own SEVERE count as a safeguard.
  Migrating the remaining sprockets test_apps to the esbuild/React-19 build (which
  removes the warning at the source) is tracked separately (#38/#19/#37).

### Rails 7.2 → 8.1: Opal pipeline moved off opal-rails (#20)

The blocker for Rails 8 was the Opal↔Rails asset integration, not Rails itself:

- **`opal-rails` 2.x is hard-capped at `rails < 7.3`** — it cannot resolve on
  Rails 8 (`Could not find compatible versions … opal-rails … requires rails
  >= 6.0, < 7.3`).
- **`opal-rails` 3.0** supports Rails 8 but is a rewrite: it drops the sprockets
  `//= require` Opal processor for an `app/opal/*.rb` → `app/assets/builds/*.js`
  `opal:build` step (hooked into `assets:precompile`/`test:prepare`/`spec:prepare`),
  and aborts the classic `//= require hyperstack-loader` precompile with
  `Opal::Rails::MissingEntrypointError: … app/opal does not exist`.

Rather than adopt that entrypoint rewrite (deferred to **#37**), Hyperstack keeps
the classic `//= require hyperstack-loader` sprockets pipeline and depends
directly on **`opal-sprockets`** — the gem that actually provides the sprockets
Opal processor, which `opal-rails` 2.x only wrapped. `opal-sprockets 1.0.4` has
**no rails cap** and resolves cleanly with Rails 8.1.3.

- **gemspecs (12):** rails pin `>= 7.0, < 8.0` → `>= 8.1, < 8.2`; `opal-rails`
  → `opal-sprockets '~> 1.0'`; `react-rails` pinned `~> 2.7` (the loose
  `>= 2.4.0, < 3.0` nondeterministically resolved to 2.6.2 on Rails 8, which
  would break the #29 connection_pool shim / React 17 line).
- **`hyperstack-config`:** require `opal-sprockets` (+ `sprockets/railtie`)
  instead of `opal-rails`, and port `opal-rails`' engine wiring into
  `hyperstack/rail_tie` — expose `config.opal`, append each gem's `Opal.paths`
  to the sprockets asset paths after `:append_assets_path`, push `config.opal.*`
  through to `Opal::Config`, and keep `app/{assets,views}` out of the
  eager/autoload paths. `opal-rails`' `.opal` template handler and `opal_ujs`
  asset are not ported (no `.opal` views or `opal_ujs` usage exist).
- **`rails-hyperstack` + 5 spec test_apps:** `require 'opal-sprockets'`.

Verified: `assets:precompile` compiles the full Opal `hyperstack-loader` bundle
(3.6 MB `application.js`) on Rails 8.1.

### hyper-spec: harness route registration on Rails 8 (#20)

`RailsControllerHelpers`' `disable_clear_and_finalize`/`clear!`/`draw`/
`routes_reloader`/`finalize!` dance no longer registers the
`GET /hyper_spec_test/:id` harness route on Rails 8 — every `mount`/`on_client`
spec failed with `ActionController::RoutingError (No route matches [GET]
"/hyper_spec_test/N")` (surfaced client-side as a 404 loading the test page, so
nothing rendered). Switched to Rails' supported `routes.append` +
`reload_routes!`, which survives route reloads and finalization. hyper-component
`base_spec`/`dsl_spec` went 3/3 red → 25 examples green.

### ActiveRecord: `enum` positional signature (#20)

Rails 8 removed the keyword-hash `enum` form. `enum test_enum: [:yes, :no]` now
raises `ArgumentError: wrong number of arguments (given 0, expected 1..2)`,
failing to load the model. The three test_app `User` fixtures moved to the
positional form `enum :test_enum, [:yes, :no]`. Isomorphic models are safe
either way — the client-side (ReactiveRecord) `enum` is a no-op — so this is a
pure ActiveRecord requirement (documented in the upgrade guide for apps).

### Ruby 3.4.9 → 4.0.5 (#15)

Latest stable Ruby (2026-05-20); the CI `base24:yjit` image already ships it.
`.ruby-version` (root) and CI `RBENV_VERSION` 3.4.9 → 4.0.5. Native extensions
(`mini_racer`/`libv8-node`) recompile clean on the 4.0 ABI; Opal 1.8.3 (which
runs on the host Ruby) is unaffected. The gem-cache key already includes
`$RBENV_VERSION`, so 3.4- and 4.0-built caches don't mix.


---

## The Rails 7 line (`rails-7`)

## 1.0.alpha1.8.34.18.72.1902.4 — 2026-07-03

### Bug fixes

- **React 18/19: restore `rescues`/`WhileLoading` recovery for non-idempotent
  render errors (#39).** On React ≥ 18 (`createRoot`, concurrent renderer), a
  render error whose condition is consumed on the first raise (a transient error,
  or the common `raise_error!` + reset idiom) silently stopped triggering its
  `rescues` block — the fallback never rendered. React 17's legacy root unwound a
  render throw **straight** to the nearest error boundary; React ≥ 18 first tries
  to *recover* by re-rendering the whole root once (`Minified React error #520`)
  and only escalates to `componentDidCatch` if that recovery render **also**
  throws. Because the error trigger was already cleared, the recovery render
  succeeded and the boundary never fired. (`flushSync` does not help — `createRoot`
  always renders through the concurrent reconciler.) `_render_wrapper`
  (`hyper-component .../component.rb`) now catches `StandardError` from render,
  stashes it, and re-raises it on **every** subsequent render so the recovery
  re-render(s) also throw and React escalates to the boundary, restoring the
  React-17 contract. The error persists until the boundary actually handles it
  (`RescueWrapper#after_error` clears it before `force_update!`) rather than for a
  fixed number of retries — React's **development** build additionally re-invokes
  a throwing render to replay the error, so the number of re-renders before the
  boundary fires is not fixed (1 in production, 2+ in development). `NotQuiet`
  (the WhileLoading "waiting on resources" signal — `< Exception`, not
  `StandardError`, and idempotent) is left to propagate on its own, which is why
  plain while-loading already worked; only the non-idempotent explicit-`rescues`
  path regressed. Validated on the react-rails React 18.2 **development** build
  (matching CI): `while_loading_spec` 7/0 (incl. "while loading works along side
  rescues") + a new hyper-component non-idempotent-rescue regression case on the
  React 19.2 esbuild build. Related: #28 (flushSync/batching), #38 (Rails 8
  client-runtime).

- **React 18/19: silence the benign top-level-`createRoot` deprecation on the
  sprockets path so it stops failing SEVERE-error assertions (#39).** On the
  sprockets path (`react/react-source-browser` UMD), react-rails' `react_ujs` and
  Hyperstack's own mount path both call the top-level `ReactDOM.createRoot`; React
  18+ logs a `console.error` deprecation on every access ("importing createRoot
  from react-dom … not supported … import it from react-dom/client"). The UMD
  bundle exposes no separate `react-dom/client` global to import from, so on this
  path the warning is unavoidable (the esbuild build avoids it by exposing
  react-dom/client's createRoot). It is harmless but is logged at **SEVERE**,
  which broke specs that assert on the *count* of console errors
  (`hyper-model server_method_spec` "will allow remote access to methods", which
  expects exactly the two 403s). `hyper-component` now drops **just that one
  message** client-side (installed once, in the Opal-only boot block), and
  `server_method_spec` also filters it from its own SEVERE count as a safeguard.
  Migrating the remaining sprockets test_apps to the esbuild/React-19 build (which
  removes the warning at the source) is tracked separately (#38/#19/#37).

## 1.0.alpha1.8.34.18.72.1902.3 — 2026-07-02

### Bug fixes

- **esbuild install: cancel hyper-router's `react-router-source` (#32).** The
  esbuild/jsbundling install path cancels the react-rails react-source imports
  (React comes from the esbuild window-globals bundle) but left hyper-router's
  `Hyperstack.js_import 'hyperstack/router/react-router-source'` (`hyper-router.rb:5`)
  active. Its bundled old react-router then loaded a **second** react-router
  against React 18/19 and threw a minified React error, blanking every component
  tree under `Hyperstack::Router`. `cancel_react_source_import` now also cancels
  `hyperstack/router/react-router-source`; the esbuild runtime templates already
  import react-router/react-router-dom/history and expose
  `ReactRouter`/`ReactRouterDOM`/`History` as window globals (the names
  hyper-router's `defines:` lists), so the cancelled source is fully replaced.
  `cancel_import` is a safe no-op when hyper-router isn't present, so this is
  unconditional (no Gemfile guard, which could miss a transitive hyper-router).

## 1.0.alpha1.8.34.18.72.1902.2 — 2026-07-02

### Rebased onto `edge` (#33, #34, #36)

Rebased the rails-7 line onto `edge`, picking up the hyper-model client-side
fixes for the integer `NaN` conversion (#34) and the broadcast `integrity_check`
UTC-vs-local datetime false positive (#33), plus the CI Bundler `~> 4.0` bump
(#36). See the `…61.1614.6` entry below for the details of those changes.

### Dependencies: unblock connection_pool 3.x (#29)

react-rails 2.7.1 (dormant upstream, last released 2023-05-19) builds its
server-rendering pool with a *positional* options hash —
`ConnectionPool.new({ size:, timeout: })` — which **connection_pool 3.0 rejects**
(3.0 switched `ConnectionPool.new` to keyword args `size:`/`timeout:`), raising
`ArgumentError` at boot. That forced a `connection_pool < 3.0` pin across every
Hyperstack gem.

A narrow shim in hyper-component
(`internal/component/rails/server_rendering/connection_pool_patch.rb`, required
right after `require 'react-rails'` and before its railtie initializers call
`reset_pool`) redefines `React::ServerRendering.reset_pool` to build the pool with
real **keyword arguments**. That form is accepted by **both** lines — natively on
3.x, and folded back into the legacy positional options hash on 2.x under Ruby 3 —
so the `< 3.0` pin is dropped from all gem Gemfiles (and the test_app) and
connection_pool moves to **3.x**. Verified that the unpatched `reset_pool` raises
`ArgumentError` on connection_pool 3.0.2 while the patched one builds the pool.

react-rails itself stays in the bundle (it's the narrow, reversible Option 2 from
#29); the full move off react-rails — replacing `react_ujs.mountComponents` and the
`server_rendering` machinery, which also retires this shim — is left for the Rails 8
work (#20).

## 1.0.alpha1.8.34.18.72.1902.0 — 2026-06-29

### React 19.2 (#18/#19)

Moved the client + server line **React 18.3.1 → 19.2.7**; version bumped
`…72.1803.0` → **`…72.1902.0`**. Builds on the React 18.3 createRoot rewrite below;
every change is feature-detected so React ≤18 still works. The **full suite is
green on React 19.2.7** (all gems; hyper-component 307 examples, 0 failures),
verified on Chrome 140 (matching CI).

- **`createRoot`/`hydrateRoot` moved to `react-dom/client`** (removed from the
  `react-dom` top-level entry in 19; only `flushSync` etc. remain). `react_runtime.js`
  imports them from `react-dom/client` and exposes them on `ReactDOM` — also the
  canonical warning-free path on 18, so it **replaces the old `usingClientEntryPoint`
  internals hack** (gone in 19). The per-container root cache (`__hyperstackReactRoot`)
  is kept so react-rails' `react_ujs.mountComponents` and Hyperstack's mount path
  don't `createRoot` the same node twice.
- **`element.ref` removed** (ref is a regular prop now). `Element#set_native_attributes`
  reads the ref from `props.ref` on React ≥19 (branching on `React.version`) and keeps
  `element.ref` for ≤18, so the removed getter is never accessed on 19.
- **`propTypes` validation removed** (`checkPropTypes` no longer runs). Hyperstack
  delivered its `param` type-checking as a `propTypes` validator, which went silent;
  `react_wrapper.rb` now runs the validator itself in `render` and `console.error`s
  in React's format (guarded to React ≥19 so ≤18 doesn't double-warn, de-duped).
- **Uncaught render errors** are routed to the root's `onUncaughtError` in 19 instead
  of being thrown out of `flushSync`. `react_api.rb` passes `onUncaughtError`, stashes
  the error, and re-throws after `flushSync`, so the mount contract holds (a
  `NoMethodError` in `render` reaches the caller). Ignored on ≤18.
- **SSR `MessageChannel` polyfill:** React 19's `react-dom/server` scheduler
  instantiates a `MessageChannel` at module-load, which the mini_racer/V8 prerender
  isolate lacks (the React 18 `TextEncoder` situation, one version on). Added a no-op
  polyfill alongside the existing TextEncoder one.
- **test_app builds the React bundle in production mode.** React 19.2's *development*
  build emits "Performance Tracks" (`performance.measure(name, {detail})`) whose detail
  carries Opal functions; **Chrome 140's chromedriver (CI) can't structured-clone them**
  ("could not be cloned"), crashing the wrapper-reuse spec — Chrome 149 (local) tolerated
  it, so it only showed on CI. The esbuild config defaulted `NODE_ENV` to `development`;
  it now defaults to **production** (matching the generator), which strips those dev-only
  measures. Override with `NODE_ENV=development`.
- **rails-hyperstack generator** scaffolds the same React 19 setup for new apps:
  `react-dom/client` createRoot/hydrateRoot (+ root cache), the MessageChannel polyfill,
  and `react`/`react-dom` `^19.0.0`.

### hyper-model: undefined-safe `Collection#count` (#31)

Under Opal 1.8.3 / Ruby 3.4 an **unloaded** `ReactiveRecord::Collection` can have its
count resolve to raw JS `undefined`, so `empty?` / `count` / the ancestor count check
crashed on first render with `undefined.$zero?` (blanking the whole component tree).
`_count_internal` now coerces `undefined`/`null` to `0` at its single return point,
covering all callers; the `load_from_db` side effects and `@count = 1` fallback are
untouched. Spec `batch2/collection_count_undefined_spec.rb` reproduces the symptom by
injecting a collection whose `count` returns `undefined`. Landed on `edge` (!45) and
`rails-7` (!46).

### Client hot reloader auto-boots on import (#30)

Importing `hyperstack/hotloader` only **defined** the class — nothing called
`Hyperstack::Hotloader.listen`, so a fresh app's browser never opened the
websocket and hot reload silently did nothing (the explicit `listen` boot was
lost in the hyperloop → hyperstack import-system refactor, last seen in
`90a3c7dc4`). `hotloader.rb` now adds `self.boot!`, invoked at file scope: it
calls `listen` automatically when the client bundle loads, **guarded to a real
browser** (window/document/WebSocket present) so it is a no-op during
prerendering and on the Rails server; it reads port/ping from the
`Hyperstack.hotloader.*` JS config and defers via `setTimeout` so the rest of
the bundle loads first. `listen`'s hyper-component touchpoints are guarded so
the hot-loader also works in a minimal bundle that does not pull in
hyper-component. New specs `hotloader_server_spec` (deterministic server-side
message building) and `hotloader_client_spec` (`js:true`; proves the client
auto-connects on page load and evaluates server-pushed code), plus a new
[`hot-reloading.md`](./docs/rails-installation/hot-reloading.md) guide.

### Test-suite stability & Ruby 3.4 warnings

- **`hyper-spec` filters Ruby 3.4 chilled-string deprecation warnings (#19).**
  A new `hyper-spec/internal/warning_filter.rb` suppresses the chilled-string
  ("literal string will be frozen") deprecations Ruby 3.4 emits from dependency
  code, keeping the console-cleanliness specs green.
- **Hardened the flaky `hyper-operation` client-side execution steps.** The
  `Operation execution (client side)` rspec-steps sequence intermittently
  failed with `undefined method 'get_round_tuit'` (e.g. hyper-operation:part2
  in pipeline 5821, green on a plain retry of the identical commit). The
  helpers were injected only at the first step's *mount* via
  `on_client`/`before_mount`; if hyper-spec re-mounted the page mid-sequence
  (`insure_page_loaded` reloads whenever `Opal` momentarily looks absent,
  widened by `get_round_tuit`'s async `after(0.2)` timer) the definitions were
  wiped and the next step blew up. Fix is spec-only: (re)define the helpers as
  a top-level script immediately before every client evaluation (hooking
  `evaluate_ruby`), so they are reinstalled after any pending re-mount.
  Verified with 5 consecutive green Dockerized-Chrome runs.

### React 18.3 — mount-API rewrite (createRoot) (#18)

Moved the client + server line to **React 18.3.1**; version bumped
`…72.1700.0` → **`…72.1803.0`**. React 18 removed `ReactDOM.render` /
`unmountComponentAtNode`, so the mount path was rewritten (all feature-detected,
so React 17 still works):

- **`react_api.rb`**: render/unmount use `ReactDOM.createRoot` — one root per
  container, kept on the node for re-render + `root.unmount()`. `createRoot.render()`
  returns nothing, so the component instance is recovered via a callback ref +
  `flushSync` (restores Hyperstack's mount→instance contract); the mounted DOM node
  is read from `container.firstChild`, not the deprecated `findDOMNode`.
- **`findDOMNode` removed (deprecated in 18, gone in 19):** `Component#dom_node`
  resolves the DOM node via the rendered Element's **ref chain** (host-element refs
  capture the node directly); for **foreign** (non-Hyperstack) class components it
  **walks the React fiber** (`_reactInternals`) to the first host node — the same
  result `findDOMNode` gives, without the hard-coded deprecation `console.error`.
  findDOMNode warnings: **66 → 0**.
- **`force_update!` / `set_state!`** keep the synchronous-update contract via
  `flushSync`, but **skip it while React is already rendering/committing** (render +
  every lifecycle method is flagged): flushSync there warns *and* refuses to flush,
  so a plain `forceUpdate` is used instead — fixes "flushSync called from inside a
  lifecycle method" (force_update! in `after_mount`, `mutate` during render). The
  broader batching trade-off this implies is tracked in #28.
- **`ReactDOM.createRoot` is warning-free *and* cached per container**: routed
  through the react-dom/client client-entry flag using the *captured* original (a
  naive alias recurses), and now **reuses one root per node**, so react-rails'
  `react_ujs.mountComponents` and Hyperstack's mount path don't call `createRoot`
  twice ("already passed to createRoot"). Unmount clears the cached root.
- **`spec/client_features/react18_spec.rb`** covers createRoot mount/unmount, root
  reuse, synchronous + in-lifecycle `force_update!`/`set_state!`, warning-free mount,
  `dom_node`-via-refs, and the foreign-component fiber walk. The **full
  hyper-component suite is green on React 18.3.1 (307 examples, 0 failures**;
  findDOMNode / flushSync / createRoot-twice warnings all 0). Spec updates for React
  18: `contextual_renderer` drops the `data-reactroot` assertions (renderToString no
  longer emits it); `state_spec` "ignores updates during rendering" counts only
  SEVERE console entries (prerendering now replays server `require` logs as INFO).

### Asset pipeline: esbuild + jsbundling-rails, off the Webpacker lineage (#19/#21)

Replaced the Webpacker lineage with **esbuild via `jsbundling-rails`**; **Opal
stays on sprockets** (the validated hybrid from #19).

- React (+ ReactDOM/ReactDOMServer/createReactClass, and react-router/history in
  the generator) are delivered as JS globals from an esbuild **IIFE** bundle
  (`react_runtime.js` → `window`; `--format=esm` would break the global-bridge);
  output to `app/assets/builds`, served by sprockets, `//= require`d ahead of the
  Opal loader.
- **`jsbundling-rails`** runs the `build` script and hooks `javascript:build` into
  `assets:precompile`, so CI builds the bundles (Node 24 now ships in the `base24`
  CI image; `SKIP_JS_BUILD` for the local no-Node flow). Uses **yarn**.
- **rails-hyperstack generator (#21):** `hyperstack:install` scaffolds the esbuild
  setup (was Webpacker); MUI/Bootstrap installers add npm components via
  `react_runtime` + `yarn build`. `--skip-webpack` remains as the pure-sprockets /
  no-Node fallback (Hyperstack's bundled React). Generated apps are on **React
  18.3.1** too (`react`/`react-dom` `^18.3.1`): the emitted `react_runtime.js` ships
  the warning-free/cached `createRoot` wrapper and the `react_server_runtime.js`
  imports the TextEncoder polyfill — so a freshly generated app matches the test_app.
- `opal-jquery ~> 0.5` added to the hyper-component test_app (its Opal bundle
  imports `jquery`, needed for `assets:precompile`).
- **Residual Webpacker/Shakapacker dead code removed (#19)** now that no app
  loads Webpacker: dropped `handle_webpack` / `cancel_webpack_imports` /
  `auto_import_webpack_bundles` (`hyperstack-config/imports.rb`), the
  `WebpackerManifestContainer` require + fallback (`hyper_asset_container.rb`),
  the `webpack_bundle_control_spec`, the legacy `bin/webpack*` +
  `config/webpack/*` / `webpacker.yml`, and the old install generator's
  Webpacker path. The deliberate `--skip-webpack` pure-sprockets fallback and
  the prerendering (#6) Opal-backtick fix in `js_imports.rb` are kept.

### Server-side prerendering restored (#6)

Prerendering works again, on React 17/18 + mini_racer.

- **Root cause fixed in `hyperstack-config/js_imports.rb`:** the js_import
  defines-check ``Opal.global['#{name}']`` relied on `#{name}` interpolating inside
  an Opal backtick — Opal 1.8 does **not**, so it compiled to the literal
  `Opal.global['name']`. Masked in the browser (`window.name` exists) but under V8
  `globalThis.name` is undefined → the check **always raised** "package React not
  found". That latent bug, not mini_racer, was why prerendering was stuck off.
- **`mini_racer`** installs cleanly now (precompiled `libv8-node 24.12`); the
  "gated off" note was stale. Re-added to the bundle.
- esbuild **server** bundle (`react_server_runtime.js`) exposes React /
  `ReactDOMServer` (`react-dom/server.browser`, V8-safe) / createReactClass on the
  Opal global; loaded as an Opal-required module at_head (after Opal boot, before
  the defines-check); `app/assets/builds` added to the Opal load path.
- **TextEncoder polyfill for the V8 prerender (#18):** React 18's
  `react-dom/server.browser` instantiates a `TextEncoder` at module-load, which the
  bare mini_racer/V8 isolate lacks (`ReferenceError: TextEncoder is not defined`). A
  guarded UTF-8 `text_encoder_polyfill.js` is imported *first* in
  `react_server_runtime.js` (ES import order installs it before React's body runs).
- `ContextualRenderer` honors `Hyperstack.prerendering_files`; the
  `contextual_renderer_spec` prerender examples re-enabled (3 examples, 0 failures).

### Infrastructure

- **`base24` CI image: Node 20 → 24 LTS** (`nodesource setup_24.x`) — supported
  Node for the esbuild build (image rebuild required to take effect).

### React 17 (version label corrected)

- **Confirmed and labelled the React 17.0.2 runtime; whole version scheme
  realigned to `…72.1700.0`.** `Gemfile.lock`s are gitignored, so CI resolves
  dependencies fresh each run — and `react-rails` 2.7.1 (required since the
  Rails 7 work) ships **React 17.0.2**, not the React 16.x the version strings
  and changelog claimed. `react-rails` 2.7.1 has no `sprockets` dependency, so
  the old `sprockets '< 4.2'` cap never held it back: the React 17 runtime was
  already live in CI and merely mislabelled. No mount-API change is needed —
  `ReactDOM.render` still exists in React 17 (its removal, and the `createRoot`
  rewrite, is React 18/19 → #18).

- **Fixed the version scheme, which had drifted across three disagreeing
  sources.** The published gem versions come from each gem's own
  `ruby/*/lib/**/version.rb`; those said `…61.1614.2` (**Rails 6.1, React 16**)
  while `HYPERSTACK_VERSION` said `…72.1614.0` and `ruby/version.rb` said
  `…72.1700.0` — so the rails-7 gems published as Rails-6.1/React-16 versions,
  and `rake publish` (which names upload files by `ruby/version.rb` but builds
  gems from the per-gem constants) would ship a mismatch. Now:
  - all 13 per-gem `version.rb` files (and `ROUTERVERSION`) → **`…72.1700.0`**;
  - `HYPERSTACK_VERSION` → `…72.1700.0`, and `ruby/version.rb` now **reads** it
    (single source of truth) instead of hardcoding a second copy;
  - new **`rake version:check`** asserts every per-gem version matches
    `HYPERSTACK_VERSION`, and `rake publish` now depends on it so mismatched
    versions can never be published again.

- **Lifted the obsolete `sprockets '< 4.2'` cap across all gem Gemfiles.** The
  ">= 4.2 can't modify immutable cached environment" error was a `react-rails`
  < 2.7 problem; verified Opal + React asset compilation work on sprockets
  4.2.2. **`connection_pool '< 3.0'` stays pinned**: `react-rails` 2.7.1's
  `server_rendering.rb` still calls `ConnectionPool.new(positional_hash)`, but
  connection_pool 3.0 switched to keyword args (`size:`/`timeout:`) — passing
  3.0 raises `ArgumentError` at boot.

### Bug fixes (ported from edge)

- **hyper-spec: replace `Parser::CurrentRuby` with `Prism::Translation::Parser`
  for parsing spec-authored blocks (#35).** `Parser::CurrentRuby` selects its
  grammar from a hand-maintained `case RUBY_VERSION` table in the `parser` gem;
  that table has no branch for Ruby 4.0 and silently falls back to the stale
  Ruby 3.3 grammar, so any Ruby 4.0-only syntax used inside a `mount`/
  `evaluate_ruby`/`on_client` block would parse incorrectly (and even 3.4.x
  prints a spurious version-mismatch warning on every spec run). `add_opal_block`
  (`client_execution.rb`), `run_on_client` (`helpers.rb`) and
  `add_block_with_helpers` (`component_mount.rb`) now go through a new
  `HyperSpec.parse_ruby` helper backed by `Prism::Translation::Parser`, which
  ships with Ruby itself (bundled since 3.3) and therefore always matches the
  grammar of the Ruby actually running the specs. `Prism::Translation::Parser`
  still emits `Parser::AST::Node` trees, so `Unparser.unparse` and the
  `find_block` AST walk needed no changes. Adds `spec/parse_ruby_spec.rb`
  covering block-arg/kwarg parsing, string interpolation, and pattern matching
  (`case/in`) round-tripping through `Unparser.unparse` unchanged.

## 1.0.alpha1.8.34.18.72.1614.0 — 2026-06-27

Major upgrade: **Rails 6.1 → 7.2** (#16). The full suite is green on **Ruby
3.4.9 / Rails 7.2.3 / Opal 1.8.3 / React 17.0.2** (via react-rails 2.7.1; the
version string's `1614` React segment was a mislabel, corrected to `1700` in a
later release). See
[`upgrade-from-rails-6-to-7.md`](./upgrade-from-rails-6-to-7.md) for the app-side
upgrade guide.

### Toolchain

- **Pinned the supported toolchain across every gemspec:** `required_ruby_version
  '>= 3.4'`, `rails '>= 7.0', '< 8.0'`, `opal '~> 1.8'`. Also `react-rails
  '>= 2.7', '< 3.0'` and `opal-rails '~> 2.0'` (the classic sprockets convention;
  opal-rails 3.0's `app/opal` entrypoint layout is a separate change).

### Rails 7 compatibility (#16)

- **`Rails.application.secrets` removed (7.2)** — transport code moved to
  `secret_key_base`.
- **`serialize` requires explicit `coder:` (7.1+)** — e.g. `serialize :data,
  coder: YAML`.
- **Guard `ActiveRecord::InternalMetadata`** (no longer an `ActiveRecord::Base`
  subclass in 7.1+).
- **rspec-rails `>= 7.0`** (lifted the stale `rspec '~> 3.11'` cap);
  `config.fixture_path=` → `config.fixture_paths=`.
- **Zeitwerk (Rails 7 is Zeitwerk-only):** `ServerDataCache.get_model` and
  `PolicyAutoLoader` now detect a *pending autoload* rather than trusting
  `const_defined?` (which is truthy for any autoloadable `app/*` constant — a
  security-relevant fix, since the old check let a client string force-load
  arbitrary classes); map `Zeitwerk::NameError` → `LoadError`; guard the classic
  `require_or_load` monkey-patch behind `respond_to?`.
- **Sprockets-only test apps:** declare `sprockets-rails`, pin `sprockets < 4.2`.
- **Generator (#21):** `rails new --skip-javascript` (avoids the importmap/Opal
  `application.js` `Sprockets::DoubleLinkError`); Zeitwerk server-side
  auto-require; `hyperstack:install` creates an App component and wires the layout
  JS; `spring stop` made non-fatal.

### Spec maintenance

- **Re-enabled the react-rails 2.7 console-format specs (#17).** The react-rails
  2.6.2 → 2.7.1 bump moved bundled React to 17.0.2 (from 16.14 on the 2.6.x
  line), which logs prop-type
  warnings as an unsubstituted `"Warning: Failed %s type: %s%s"` format string and
  drops component names from the `componentDidCatch` `componentStack` (for
  `create-react-class` components). Loosened the 11 matchers and relaxed the
  `:after_error` stack assertion accordingly.
- **Fixed the `get_model` unknown-class spec (#22).** Assert the access-violation
  guard against a name that resolves to no file and no model, so it holds in every
  environment (in-suite `public_columns_hash` require_dependency's app files, so
  no app-resident class stays unloaded). The `constant_loaded?` guard itself was
  already correct.

### Cleanup

- **Dropped the `concurrent-ruby '1.3.4'` and `net-imap '0.4.18'` pins** —
  Rails-6-on-Ruby-3.2 workarounds, obsolete on 7.2 (concurrent-ruby was forcing a
  downgrade from 1.3.7).
- **Lifted `sqlite3 '< 2'` → `'>= 2.0'`** (rails/rails#35153 long resolved).
- **Removed the dead `rails_version < '7'` cluster** from the rails-hyperstack
  Rakefile (zeitwerk/nokogiri/net-imap/concurrent-ruby install+uninstall and the
  test_app Gemfile appends); collapsed the always-true `js_skip` ternary.

