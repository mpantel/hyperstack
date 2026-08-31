# Changelog

Project-wide changelog. Version-scoped release notes for the v23–v28 Redis
connection work live in [`CHANGELOG_v23-v28.md`](./CHANGELOG_v23-v28.md);
hyper-component has its own [`CHANGELOG`](./ruby/hyper-component/CHANGELOG.md).
The releases published by the retired `rails-7` / `rails-8.0` / `rails-8.1`
branch lines are archived in
[`CHANGELOG_rails-7-and-8-lines.md`](./CHANGELOG_rails-7-and-8-lines.md).

## 1.0.alpha1.9 — 2026-08-31

The release that collapses the four release lines into one. Since
`1.0.alpha1.8.34.18.61.1614.6` this project maintained `edge`, `rails-7`,
`rails-8.0` and `rails-8.1` as stacked rebases of each other, each publishing its
own gem set for one Rails version. A fix landed on one line and had to be carried
by hand to the others; several never made the trip, and the drift was invisible
because nothing compared the lines. `edge` now serves all of them from a single
gem set, tested across a 10-cell matrix, and the branch lines are retired.

Two consequences are visible from outside:

- **The version number no longer encodes a configuration.** The old suffix
  (`.34.18.61.1614.6` = Ruby 3.4 / Opal 1.8 / Rails 6.1 / React 16.14 / patch 6)
  was the only record of what a build was tested against, which worked while one
  build meant one combination. It does not survive a matrix, so it is retired and
  the series returns to a plain point release. `supported_versions.yml` is now the
  compatibility statement, checked at boot by `Hyperstack::SupportedVersions` and
  from the command line by `rake hyperstack:config:check` (#51).
- **The published gems install on what they are tested on.** With no cell env set
  — exactly how `rake publish` builds — the gemspecs resolved to `rails < 7.0` and
  `react-rails < 2.7.0`, so the gem refused to install on the Rails 7.2 and 8.x it
  is tested against. See "Dependency declarations" below (#20).

### Supported configurations

Ten cells, each a pipeline. `react` is derived, not selected: it is whatever
`react_rails` plus the JS pipeline deliver.

| cell | ruby | rails | react-rails | react |
|------|------|-------|-------------|-------|
| rails61-react16 | 3.4 | 6.1 | 2.6 | 16.14 |
| rails61-react17 | 3.4 | 6.1 | 2.7 | 17.0.2 |
| rails61-react18 | 3.4 | 6.1 | 3.3 | 18.2 |
| rails61-react19 | 3.4 | 6.1 | 3.3 | 19.2 (npm) |
| rails72-react16 | 3.4 | 7.2 | 2.6 | 16.14 |
| rails72-react19 | 3.4 | 7.2 | 3.3 | 19.2 (npm) |
| rails80-react19-ruby34 | 3.4 | 8.0 | 3.3 | 19.2 (npm) |
| rails80-react19-ruby40 | 4.0 | 8.0 | 3.3 | 19.2 (npm) |
| rails81-react19-ruby34 | 3.4 | 8.1 | 3.3 | 19.2 (npm) |
| rails81-react19-ruby40 | 4.0 | 8.1 | 3.3 | 19.2 (npm) |

Opal is `~> 1.8` throughout. An app outside these spans is reported
`:unsupported` and raises; one inside them but not on a cell is `:untested` and
warns once, naming the nearest tested cell.

### Spec suite timings

Measured on pipeline 6829 — `edge` at `24b4a409a`, the commit this release is cut
from — with all 121 test jobs green.

**Hardware.** A single host, `ru-vm2`: **16 cores, 32 GB RAM, 15 GB swap**, Docker
executor, GitLab Runner 19.3.1 on linux/amd64. Hyperstack has no dedicated runner;
its jobs are served by two runner registrations on that host — id 4 (`limit = 5`)
and id 7, "unprotected" (`limit = 12`) — under a global `concurrent = 22`. So at
most **17 jobs run at once**, and this pipeline hit exactly that ceiling: peak 17
concurrent, 33 jobs on the first registration and 88 on the second.

Those limits are current as of 2026-08-29 and were lowered that day, from 20/28,
after the kernel OOM-killer fired three times on 2026-08-28 killing a `chrome`
inside a job container. The matrix widening from 6 to 8 cells (90 → 120 jobs) had
made a single `edge` pipeline able to fill the runner by itself. A brief upgrade
to 32 cores / 62 GB was walked back the same week on the reasoning that more cores
do not lower per-job memory footprint — Chrome, ruby and `cc1` need the same RAM
regardless — so the ceiling here is memory, not CPU.

**Totals.** 60 minutes wall clock for the test stage. 7 h 20 min (26,395 s) of
aggregate runner time across 121 jobs: 12 gem jobs × 10 cells, plus the
once-per-pipeline `supported-versions` check.

Per job, in seconds, across the ten cells:

| job | min | median | max |
|-----|----:|-------:|----:|
| hyper-model | 608 | 734 | 762 |
| hyper-component | 504 | 508 | 513 |
| hyper-spec | 269 | 285 | 301 |
| hyperstack-config | 169 | 250 | 265 |
| hyper-operation:part1 | 181 | 198 | 203 |
| rails-hyperstack | 139 | 144 | 252 |
| hyper-operation:part2 | 119 | 130 | 139 |
| hyper-store | 106 | 113 | 122 |
| hyper-i18n | 81 | 87 | 93 |
| hyper-router | 81 | 86 | 90 |
| hyper-state | 75 | 85 | 93 |
| hyper-trace | 27 | 33 | 36 |
| supported-versions | — | 52 | — |

hyper-model is the critical path at ~12 minutes, and is why it runs as 7 batches
in 4 concurrent rspec processes; hyper-operation splits into two parts for the
same reason.

Per cell, total runner seconds for its 12 jobs:

| cell | total |
|------|------:|
| rails61-react18 | 2736 |
| rails61-react19 | 2735 |
| rails61-react16 | 2726 |
| rails61-react17 | 2722 |
| rails80-react19-ruby40 | 2712 |
| rails72-react19 | 2678 |
| rails72-react16 | 2589 |
| rails81-react19-ruby34 | 2502 |
| rails80-react19-ruby34 | 2491 |
| rails81-react19-ruby40 | 2452 |

The spread across cells is under 12%, which is the point worth taking from this
table: no configuration in the matrix is meaningfully more expensive than another,
so the cost of a cell is essentially fixed and adding one is a capacity decision
rather than a performance one.

Two caveats on reading any of these numbers. They are **with** the prebaked cell
images (#57, #73, #75), which took roughly 200 s + 95 s off each rails61 job and
removed a ~58 s cache restore from every job; before that work the same suite cost
substantially more. And the host is shared — `ru/hyperstack-addons` runs on the
same two registrations, and five other runners share the machine — so co-scheduling
moves these figures, and a job that looks slow is often contended rather than
regressed.

### Security

- **hyper-model: a save or destroy by id now requires read access to the record
  (#50).** `find_record`/`destroy_record` resolved an incoming primary key with a
  bare `Model.find(id)`, leaving `create_permitted?`/`update_permitted?`/
  `destroy_permitted?` as the only gate. Those policies are very often written as
  "is someone signed in" — the natural place to ask "does this record belong to
  the acting user" being the read regulations — so a client could send the id of
  *any* record of that model, have its own permissive change policy evaluated
  against it, and then have every attribute in the request written to it. The
  `save: false` branch already replayed the client's vector through the regulated
  `__secure_remote_access_to_*` path; only the write branch skipped it. Rather
  than replay the vector on the write path (client vectors go stale — a `*N`
  collection index can come to point at a different row — so a strict replay
  would reject legitimate saves), the record is resolved as before and the acting
  user must then be able to *read* it, via the same
  `check_permission_with_acting_user(acting_user, :view_permitted?, :id)` the read
  path uses. The bar is low enough not to break working apps:
  `accessible_attributes_for` includes `:id` whenever any attribute of the record
  is broadcast to this browser. `Hyperstack.verify_record_visibility_on_write =
  false` restores the old behaviour. The unchecked mass-assignment half of #50 —
  every attribute the browser sends is written before the change policy runs — is
  documented in `docs/policies` and the hyper-model gotchas rather than changed.

- **hyper-model: close the second half of the `get_model` constant gate (#60).**
  `ServerDataCache.get_model` consults two gates and only one had been hardened.
  `LazyColumnsHash#key?` still fell back to `Object.const_defined?`, which under
  Zeitwerk is true for every class in `app/*` — each has a registered autoload at
  boot — so a client-supplied string could be declared a "public model" and then
  autoloaded. The predicate ("defined AND no pending autoload", via
  `owner.autoload?(leaf)`) moves into `ReactiveRecord::ConstantGate.loaded?`,
  which both `ServerDataCache.constant_loaded?` and `key?` now call. `key?`
  returns true first for `@loaded_models` entries and for names matching a
  `@file_paths` entry, so legitimately-unloaded lazy public models still resolve.
  The Zeitwerk-safe gate in `server_data_cache` itself came across from the
  rails-7 line with #43.

### Rails 7 and Rails 8 support

Every one of these was already fixed on a branch line and stranded there. None
required a Rails-version branch in library code — all are capability checks that
are correct on 6.1 and on 8.1 alike (#52, #51).

- **hyper-model: `ActiveRecord::InternalMetadata.do_not_synchronize` is guarded.**
  Rails 7.1+ made `InternalMetadata` a plain class rather than an
  `ActiveRecord::Base` subclass, so it no longer has `do_not_synchronize` and does
  not participate in sync anyway. edge called it unconditionally and the gem
  failed to load outright with
  `Bundler::GemRequireError: undefined method 'do_not_synchronize'`.

- **hyper-component / hyper-model: `fixture_paths=` replaces `fixture_path=`.**
  rspec-rails 7, pulled in by Rails 7, removed the singular form, so every example
  group failed to load. Written as a `respond_to?` check.

- **hyper-store / hyper-state / hyperstack-config: relax the rspec cap (#52).**
  Those three pinned `rspec '~> 3.11.0'`, which caps rspec-core at 3.11 and so
  blocks rspec-rails 7+. Relaxed to `'~> 3.11'` — a range rather than rails-7's
  `rspec-rails >= 7.0`, which would be uninstallable on Rails 6.1.

- **hyper-operation: `serialize :data` needs an explicit coder on Rails 7.1
  (#52).** A bare `serialize` raises there. Guarded on
  `::ActiveRecord.version >= 7.1` to pass `coder: YAML`, keeping YAML so existing
  rows still read. The broken serialize meant connections never registered and
  every ActionCable transport spec saw `Hyperstack::Connection.active == []`.

- **hyper-operation: use `secret_key_base`, not the Rails-7.2-removed
  `application.secrets` (#52).** `Hyperstack.authorization` computed the channel
  authorization SHA1 from `Rails.application.secrets[:secret_key_base]`. Rails 7.2
  removed `Rails.application.secrets` entirely, so every channel authorization
  failed, no connection became active and no broadcast arrived. Now reads
  `Rails.application.secret_key_base`, available since Rails 4.1.

- **hyper-operation: the Zeitwerk autoloader contract for policy files (#52).** A
  policy file that exists but fails to define its constant must propagate as a
  `LoadError`. The classic autoloader raised exactly that; Zeitwerk raises
  `Zeitwerk::NameError`. `transport/policy.rb` converts the latter back behind
  `defined?(Zeitwerk::NameError)`, so the contract holds on both.

- **hyperstack-config: guard the classic-autoloader hooks removed in Rails 7
  (#52).** `server_side_auto_require.rb` aliased
  `ActiveSupport::Dependencies.require_or_load` at load time, which no longer
  exists and raised `NameError` during `rails generate model`; the alias is now
  wrapped in `if respond_to?(:require_or_load, true)`, correct because under
  Zeitwerk the `loader.on_load` hook already covers shadowed server-side files.
  More insidiously, `Rails.configuration.try(:autoloader) == :zeitwerk` is
  *silently false* on Rails 7 (`config.autoloader` was removed), so the `on_load`
  hook was never installed and server-side shadow files quietly stopped loading.
  Replaced with `Rails.respond_to?(:autoloaders) &&
  Rails.autoloaders.zeitwerk_enabled?`.

- **hyper-model: `primary_abstract_class` is a no-op on the client (#43).**
  Rails 7+ generates `class ApplicationRecord < ActiveRecord::Base;
  primary_abstract_class; end`, and `hyperstack:install` moves `ApplicationRecord`
  into `app/hyperstack` so it compiles to the client too — where that server-only
  macro is undefined and raises on boot, corrupting the reactive-record model
  layer so client-created records never sync. Inert on Rails 6.1.

- **Rails 8: Opal reaches sprockets through opal-sprockets (#20, #15).**
  opal-rails 2.x is hard-capped at `rails < 7.3` so it cannot resolve at all on
  Rails 8, and opal-rails 3.0 replaces the sprockets processor with an `app/opal`
  entrypoint build — a separate change (#37). A new `OPAL_SPROCKETS_VERSION`
  selector swaps `opal-sprockets` in for `opal-rails` in the gemspecs, and the
  Rails wiring `Opal::Rails::Engine` used to provide — `config.opal`, trimming
  `app/assets` out of `eager_load_paths`, unshifting `Opal.paths` after
  `:append_assets_path`, and pushing `config.opal.*` into `Opal::Config` — is
  ported into `Hyperstack::Railtie`, activating only `unless
  defined?(::Opal::Rails::Engine)`. `SQLITE3_VERSION` comes with it, because Rails
  8's SQLite3 adapter needs sqlite3 2.x against the gemspecs' `< 2` pin.

- **hyper-spec: register the harness route with `routes.append` on Rails 8 (#20).**
  The old `disable_clear_and_finalize` / `clear!` / `draw` / `finalize!` dance no
  longer registers the route there, and every mount spec died with
  `No route matches [GET] "/hyper_spec_test/N"`. Gated on
  `Rails::VERSION::MAJOR >= 8`.

- **hyper-spec: emit `Opal::Sprockets.load_asset` for `.rb` assets (#20).**
  opal-sprockets does not append the `Opal.load(...)` bootstrap to the compiled
  asset the way opal-rails did, so the module stayed registered in `Opal.modules`
  and never executed.

- **hyper-model: the columns hash must be JSON-serializable on Rails 8.1 (#81).**
  The root cause of the entire Rails 8.1 breakage, and a good example of a latent
  fault that only a new cell could find.
  `ActiveModel::Type::Value#as_json` is `raise NoMethodError`, deliberately, and
  it is identical in Rails 8.0 — so the `Column` objects hyperstack serializes
  were never serializable; nothing had asked them. ActiveSupport 8.1 swapped its
  JSON encoder for `JSONGemCoderEncoder`, which calls `as_json` on every value
  outside a small set of primitives, so 8.1 asks and the raise takes the page
  render with it. That single exception is the whole of #81: the 500 truncates the
  harness page's inline script (`Uncaught SyntaxError: Unexpected token '}'`), the
  client never receives the columns hash and so does `JSON.parse(undefined)`, and
  then 1774 × `ReactiveRecord.load exception ... undefined method '[]' for nil`.
  The wire shape is deliberately unchanged — exactly what `Object#as_json`
  produced before, because the client reads `[:sql_type_metadata][:type]` and
  `[:default]` out of it and that shape already works on 6.1, 7.2 and 8.0. Only
  the unserializable leaf is replaced, with the type's name, which is the single
  thing the client wanted from it. Sanitization recurses through `instance_values`
  rather than delegating to `Object#as_json`, so a `Type::Value` nested anywhere
  inside is caught rather than raising three levels down where the backtrace does
  not say which column.

- **hyper-model: sanitize at the JSON boundary, not the call site (#81).** The
  first cut applied the fix in `public_columns_hash_as_json`, which covered the
  render path and nothing else; three specs call the serialization directly and
  still raised. Moved into `LazyColumnsHash#as_json` — which is also what
  ActiveSupport 8.1's encoder calls on the way through — covering the render path
  and the direct callers at once.

- **hyper-model: sanitize where both builders converge (#93).** `public_columns_hash`
  has two builders: `build_lazy_columns_hash` returns a `LazyColumnsHash` (which
  sanitizes) while `build_eager_columns_hash` returns a plain Hash extended with a
  module (which did not). On the eager path the raw `Column` objects still reached
  Rails 8.1's encoder and re-raised, 500ing the harness route — the source of every
  downstream "Opal is not defined" on that cell. Sanitization moves to
  `json_safe_columns(pch.to_h).to_json`, and is idempotent so the lazy path passing
  through both is harmless.

- **hyper-model: do not expand values that already serialize themselves (#92).**
  A regression introduced by the first cut of #81, not a Rails 8.1 behaviour
  change. `json_safe_columns` expanded everything non-scalar through
  `instance_values`, which is wrong for any value that has a real `as_json` but no
  instance variables — `Date` and `Time` being exactly that. They expanded to `{}`
  and the column default was destroyed. The damage surfaced a long way off: the
  date column's default reached the client as `{}`, `DummyValue#initialize` called
  `Date.parse({})`, the bare `rescue ::Exception` there swallowed the error, and
  the attribute read back as `nil`. `Date` and `Time` are now leaves, and the
  expansion branch additionally refuses to expand anything whose `instance_values`
  are empty — the general form of the same rule.

- **hyper-model: key the `ServerDataCache` tree's id with a String (#82).**
  `as_hash` did `children.merge(id: id)` with a Symbol while every other key was a
  String, so any node whose record had also had its `id` attribute fetched carried
  both `:id` and `"id"` — which collapse to one duplicate `"id"` in JSON.
  ActiveSupport warns about that today; json 3.0 raises. Keyed `'id'`, with the
  `load_from_json` readers and `class_methods.rb`'s `_react_param_conversion`
  vector building updated to match.

### React 16 through 19 from one code line

- **hyper-component: the React 18 `createRoot` path (#51).** edge could not run
  React >= 18 at all — `react_api.rb` had zero `createRoot` references, and React
  18 removed `ReactDOM.render`. Taken from the rails-7 line (10 files). The code
  needs no version branching: it feature-detects and keeps every path
  (`createRoot` → `ReactDOM.render` → `findDOMNode` → `unmountComponentAtNode`).
  The one genuine difference was the Webpacker server-rendering container, which
  react-rails 2.x ships and 3.x dropped; rails-7 simply deleted the require, and
  since both majors are now supported it comes back behind a `LoadError`/`defined?`
  guard.

- **hyper-component: prop-warning and component-stack specs are React-17 aware
  (#51).** The React 17 cell surfaced 12 failures, all test expectations rather
  than component code. React ≤ 16 interpolated its warnings before handing them to
  `console.error`; React 17 passes the format string and its arguments separately.
  `console_messages` now re-interpolates before matching, so the assertions stay
  written against the readable form on either version. Separately, React 17
  replaced the synthetic component stack with native error frames, so the
  non-empty `componentStack` is asserted unconditionally and the
  component-by-component form only on React ≤ 16.

- **React 19 from npm, in every gem's test_app (#40).** react-rails tops out at
  3.3 / React 18.2, so before this the React axis was frozen at 18 no matter what
  the table said. New `ruby/test_app_react_source.rb`, invoked from each gem's
  `spec:prepare`, rewrites the committed app in place when
  `HYPERSTACK_REACT_SOURCE=npm`: it installs the same four templates the esbuild
  generator uses (extracted out of `esbuild.rb`'s heredocs so the two cannot
  drift), inserts `//= require react_runtime` before `hyperstack-loader`, and
  strips *every* `Hyperstack.import 'react(-server)'` — including hyper-i18n's
  indented one and hyper-component's client-side `react-server`, which together
  caused 185 "Minified React error #525" failures from two Reacts in one page,
  not a React 19 incompatibility. `app/assets/builds` is inserted *early* in
  `config/initializers/assets.rb`, since appending lands after Opal's load-path
  array is frozen, and rewritten files are backed up under `.react_source_backup`
  so a local checkout is not silently left on React 19. react-rails 3.3 is still
  required even where React does not come from it: it ships `react_ujs`, the
  mount/unmount shim, and that has to match the React major.

- **esbuild: let a cell select the npm React version (#51, #40).** The generated
  `package.json` hardcoded `^19.0.0`, so the React axis was selectable only on the
  react-rails path and frozen on the npm one — which is why three branch lines
  declared `react: 19.2` while actually serving 18.2. `REACT_NPM_VERSION` is now
  interpolated into both entries, pinned to a `~19.2.0` series rather than a caret
  range because `cell_contract_spec` asserts `window.React.version` against the
  table.

- **rails-hyperstack: actually cancel the sprockets React under esbuild (#66).**
  The generated app shipped a 1.2 MB React 19 bundle but ran React 16.14
  (`hasCreateRoot: false`). The base `cancel_react_source_import` is a no-op — it
  prepends a *commented-out* import line — while `rails-hyperstack.rb`
  unconditionally calls `js_import 'react/react-source-browser'`, putting the
  react-rails UMD into the Opal loader manifest; `application.js` requires
  `react_runtime` before `hyperstack-loader`, so the UMD assigned `window.React`
  last and won. The esbuild strategy now emits real `Hyperstack.cancel_import`
  calls, scoped to that strategy so the Rails 6.1 cells are untouched.

- **hyper-component: an uncontrolled `<textarea>` must ignore later values (#62).**
  React decides at mount whether to set a textarea's dirty value flag by comparing
  the rendered child text against `_wrapperState.initialValue` with `===`;
  `initWrapperState` stores `props.defaultValue` uncoerced while `getHostProps`
  stringifies it, so the check only holds for a JS string primitive. Any object
  `defaultValue` — a value object, an observable, hyper-model's `DummyValue`, or a
  boxed Opal String from a reactive-record attribute — failed it, the flag was
  never set, and React's per-render `node.defaultValue = ...` then pushed every
  later value into the visible textarea. `normalize_textarea_default_value` forces
  a primitive with `'' + value.to_s`, called only when `type == 'textarea'`;
  `<select>` is untouched because its `defaultValue` may legitimately be an Array.

- **hyper-model: the load transition must not discard what the user typed (#72).**
  `input_tags.rb` carried a late-arriving `defaultValue`/`defaultChecked` into an
  already-mounted uncontrolled element by setting a React `key` from the value's
  `loading?` state; when the key flipped true→false React discarded and re-mounted
  the DOM node, throwing away anything typed while the fetch was in flight.
  Replaced by `Tags::UncontrolledDefault`, which attaches a per-render `ref`
  (chaining any existing one), records the pending state and placeholder on the
  node itself, and on the loading→loaded transition assigns `node.value` /
  `node.checked` exactly once and only if the node still holds the placeholder —
  preserving user input while still setting the dirty value flag #62 requires.

### hyper-operation: two transports that had never delivered a broadcast

Three defects here, and they were stacked: each one had to be fixed before the
next became reachable. `#103` created the tables, which let `#104` be observed,
and rooting `#103` out exposed that the predicate behind it was wrong everywhere
else too, which is `#105`. All three are silent failures — the page simply stays
stale — and all three affect ordinary deployments, not just CI.

- **`on_server?` answered *false from inside the server* in any normal
  deployment (#105).** The predicate `send_data`, `dispatch`,
  `ReactiveRecord::Broadcast.after_commit` and the connection adapters' `active`
  all branch on was:

  ```ruby
  def self.on_server?
    return defined? Rails::Server
  end
  ```

  `Rails::Server` is defined only when the process was started through
  `rails server`. Not under Passenger, not under a container running
  `bundle exec puma` or `rackup`, not under Capybara's in-process server, and not
  in any rake task. So in a normal deployment every broadcast took the
  *forwarding* branch — an HTTP POST from the server to itself, landing on
  `console_update` — instead of being published to the transport. The question
  being asked is a real one, and the right one ("am I the process serving
  requests, or a console that must forward to it?"); only the way of asking it
  was wrong. It is now answered by fact rather than inference: a
  `Hyperstack::MarkServerProcess` middleware, installed by the engine, records
  that this process is serving on its first request, which is what actually
  distinguishes a server from a console or a rake task. Being middleware, it runs
  ahead of the router, so a broadcast issued from the very first request already
  sees the flag. `send_data` also gains the `Connection.root_path` test that
  `dispatch` and `Broadcast.after_commit` already had, so a process with nothing
  to forward *to* — a rake task on a box where the app has never served — queues
  the message locally instead of raising `no server running`.

- **Queued broadcasts raised `Psych::DisallowedClass` when read back on Rails
  6.1 (#104).** `#44` applied the permitted-class list only on Rails >= 7.1, and
  below that the column fell back to a bare `serialize :data`. But Rails 6.1.7.x
  carries the same safe-load backport, so `YAMLColumn#yaml_load` there is already
  a restricted `safe_load` with nothing permitted on this column: the payload
  dumps fine and raises on the way back in. `#44` fixed the dump side; this is the
  load side, and it had never been reachable — per `#103` the
  `hyperstack_queued_messages` table did not exist on Rails 6.1 at all, so nothing
  was ever queued there and nothing ever read back. Rails 6.1's `serialize`
  accepts any object responding to `dump`/`load`, so the same list is applied
  through a coder on the column rather than by widening
  `config.active_record.yaml_column_permitted_classes` — `#44`'s reasoning stands,
  that hyperstack's own table should not require the host application to widen a
  global list. Worth knowing if you meet it in an application: the raise surfaces
  from `restore_transaction_record_state` during `rolledback!`, so it presents at
  an unrelated `Model.create` rather than at the queue read.

- **The connection tables were never created unless the app was booted by
  `rails server` (#103).** The most consequential fix in this release, and the
  one most likely to be affecting a running application right now. The
  `hyperstack_connections` and `hyperstack_queued_messages` tables have no
  migration — `AutoCreate#create_table` is the only thing that ever creates them
  — and `needs_init?` gated that on `Hyperstack.on_server?`, which is
  `defined?(Rails::Server)`. That constant exists only when the process was
  started through `rails server`. It is absent under Capybara's in-process
  server, a bare `puma` or `rackup`, Passenger, and every rake task — so in any
  of those the tables were never created, `ConnectionAdapter::ActiveRecord.active`
  returned `[]` behind its own `table_exists?` guard, and every server-originated
  broadcast was discarded. Silently: that guard is indistinguishable from
  "nobody is listening", so there was no exception, no log line and no failed
  request. Both the `:action_cable` and `:simple_poller` transports are affected,
  and `:action_cable` is what `hyperstack:install` writes by default. Whether the
  current process happens to be the one serving requests has nothing to do with
  whether the tables need to exist, so the gate is dropped from `needs_init?`
  alone; `on_server?` is untouched and remains correct for `send_data` and
  `dispatch`, which use it to choose between broadcasting directly and forwarding
  to the running server over HTTP. A `StandardError` rescue keeps what the old
  gate covered by accident — with no usable database (asset precompile, a build
  container, a boot before `db:create`) `table_exists?` raises, and that must
  stay a no-op rather than become a boot failure.

  Worth recording how this was found, because it is the argument for the whole
  consolidation. It surfaced only when a spec salvaged from the retired
  `rails-8.1` line — the only place it had ever existed — was run across the
  matrix: it failed on all six Rails 6.1/7.2 cells and passed on all four Rails
  8 ones. Rails 8 passing was incidental, something on that boot path defines
  `Rails::Server`, and chasing the difference as a Rails-version behaviour change
  produced one confident wrong fix before a control printing the adapter state
  per cell settled it. No single-configuration branch line could have seen this.

- **Two faults in series, each hiding the next (#85, #87, #89, #90).** Both were
  invisible because hyperstack falls back to polling when a broadcast does not
  arrive, so the page still ended up correct and every spec passed on the fallback.
  First, the vendored client was Pusher JavaScript Library v4.0.0, from 2016, which
  has never heard of `forceTLS` — the option pusher-fake configures it with. It
  ignored it, chose its own scheme, and tried `wss://127.0.0.1` on port 443 with
  nothing listening; the only symptom was unrelated column-type and scope specs
  failing on console noise. With the socket finally up, `opts[:dispatch]` raised
  `ArgumentError: wrong number of arguments (given 2, expected 1)` on every
  broadcast: pusher-js 7 changed a channel callback from `fn.call(context, data)`
  to `fn.apply(context, args)` with a metadata argument, `Channel#handleEvent`
  always passes `{}`, and `opts[:dispatch]` was a Ruby lambda, which enforces
  arity. pusher-js runs named callbacks in a bare loop with no `try`/`catch`, so
  the raise aborted the loop and no component ever saw a broadcast. Fixed with a
  splat, and the client taken to 8.6.0 — which also replaces the `unload` listener
  Chrome 150 blocks by permissions policy with `pagehide`. hyper-console's
  prebuilt bundle carried its own embedded copy of v4.0.0 and would otherwise keep
  shipping it. Four new assertions span the chain so this cannot hide again: the
  client understands `forceTLS`, the websocket reaches `connected`, the channel
  reaches `subscribed`, and a broadcast arrives *on the pusher channel* rather
  than via the polling fallback. hyper-model also now runs in ~500s against ~981s
  on v4 — the examples stop waiting out timeouts for broadcasts that were never
  going to arrive.

- **Queued messages are no longer destroyed with a handshaking connection (#70).**
  A broadcast issued while a client had `open`ed a connection but not yet finished
  `connect_to_transport` was silently lost. `expire_new_connection_in` (default
  10s) reaps half-open connections via `Connection.expired.delete_all`, which
  cascades and destroys the connection's `QueuedMessage` rows — so a handshake
  running past the window, routine on a loaded server, took the queued message
  with it. Both connection adapters' `send_to_channel` now refresh
  `expires_at` for each pending connection they queue against: a waiting message
  proves the connection is not abandoned, while genuinely idle half-open
  connections are still reaped.

- **Queued broadcasts carry their own YAML permissions (#44).** On Rails 7.1+,
  `serialize :data, coder: YAML` routes through `ActiveRecord::Coders::YAMLColumn`'s
  safe coder, which refuses to *dump* anything outside
  `config.active_record.yaml_column_permitted_classes` (default `[Symbol]`).
  Hyperstack's queued broadcast payloads are `HashWithIndifferentAccess` with
  times, so every queued broadcast raised `Psych::DisallowedClass` — killing
  `:simple_poller` outright and making `:action_cable` drop any broadcast that beat
  the websocket handshake. `queued_message.rb` now declares
  `PERMITTED_YAML_CLASSES` and passes it on the column, so the table carries its
  own permissions rather than depending on the host app widening a global list.

### hyper-model

- **`ServerDataCache` built every vector twice (#100).** `ServerDataCache.[]`
  ran the same `inject` over the vector's methods twice — once discarding the
  result, then again into `final`:

  ```ruby
  vector[1..-1].inject(root) { |cache_item, method| cache_item.apply_method method if cache_item }
  final = vector[1..-1].inject(root) { |cache_item, method| cache_item.apply_method method if cache_item }
  ```

  `apply_method` is not free of side effects: a vector ending in a
  `server_method` *invokes* it. So every such fetch ran the method twice, and any
  server method that mutates — a counter, a log line, an external call — did its
  work twice per request. Invisible in the returned data, because the second pass
  produces the same value the caller sees.

  It surfaced as an intermittent off-by-one in
  `batch6/server_method_spec.rb:71` (`expected: 5, got: 4`), which is the shape
  that made it hard to attribute: the doubling is deterministic, but whether it
  changed the *observed* count depended on how the fetches batched, so it only
  showed under load. The duplicate pass is removed. An opt-in
  `HYPERSTACK_TRACE_VECTORS` logs each vector and the batch it arrives in, which
  is how the double-build was made visible.

  The spec's own cross-process hazard is documented alongside it in
  `AsyncExpectationTarget`, next to the #67/#83 notes: comparing a
  client-resolved value against server state read afterwards is a race that no
  amount of care about the *first* read can fix — a step that fires asynchronous
  work must settle it (`wait_for_ajax`) so the server is quiescent when the next
  step reads it. Relaxing the matcher would only have hidden this.

- **Wait for the pusher handshake before broadcasting (#70).** Diagnosed by
  instrumenting the step under a full matrix run, where the discriminator was
  exact, 4/4: passing cells created 0 `QueuedMessage`s during the step, failing
  cells created 1 and 3. `send_to_channel` has two mutually exclusive paths —
  queue if the client is still handshaking, push if transport-connected — so
  passing runs pushed and failing runs queued. The subscription was never the
  problem; the missing piece was the transport handshake, which is what runs late
  under load. Adds a shared `WaitForTransportConnection` helper (36 specs in this
  repo configure the pusher transport and share the latent race) which removes the
  race rather than widening a window.

- **Wait for the handshake before dispatching `FetchNow` (#65).** The same shape
  in the two "while loading" examples: the assertions only proved the page had
  rendered, not that the handshake had completed, so the dispatch could be queued
  against a connection that expired unread.

- **`default_value_spec` raced the fetch (#61).** Intermittently red for months
  (~3 runs in 10) and repeatedly written off as environment flakiness. It is not
  environmental. `expect(page).not_to have_content('loading...', wait: 0)` looks
  like a gate on the data having arrived but is *vacuous* — 'loading...' only ever
  appears as an option *value* attribute, never as page text, and
  `DummyValue#to_s` returns `''`. `find('#uncontrolled-input')` then waits for the
  element, which exists immediately carrying the placeholder, and `.value` is read
  once and compared with a plain `eq`, which does not retry. That fits every
  observation: ~30% failure, no correlation with cell, Rails version, React
  version or concurrency, and immunity to forcing functions applied around mount —
  because the race is between Capybara's read and the fetch, not between the fetch
  and mount. Demonstrated rather than argued: with the fetch response delayed 2s,
  the original assertions fail 4/4 cells with the identical signature and the
  waiting matchers pass 4/4.

- **`alias_attribute` regression specs, made deterministic (#25).** The
  `alias_attribute` sequence intermittently failed `implements the _changed?
  method` with `undefined method 'surname_changed?'`. The sequence runs as one
  shared-session example in a single long-lived browser, and the aliases are
  installed via `before(:step) { isomorphic ... }` — which injects code only at
  *mount* time, effectively once. A mid-sequence re-mount wiped them, and because
  `alias_attribute` installs both the alias methods and the `_attribute_aliases`
  entry in one call, it also emptied the `method_missing` dealias map. Deterministic
  single-example specs now lock the dealias contract behind the flake.

- **Make the `aaa_edge_cases` monkeypatch idempotent (#51, #38).** The example
  redefines `synchromesh_after_create` with a bare `alias` in its body; that body
  re-runs on every RSpec::Retry attempt, and the second `alias` re-points `orig` at
  the already-overridden method, so the override calls itself. Infinite recursion —
  `SystemStackError`, a 4MB truncated log, and a cascade of downstream noise that
  looks nothing like the cause. Deterministic, already fixed on another line, and
  exactly the signature that has been written off as browser flakiness.

- **Document the polymorphic / auto-inverse contract (#45).** The three log calls
  in `AssociationReflection#find_inverse` are factored into
  `warn_dynamically_adding`, which now explains why it matters: until something
  resolves the inverse the relationship does not exist on the client, so reading it
  falls through to the attribute reader and yields the target's column hash instead
  of a model. The docs state that the `unless RUBY_ENGINE == 'opal'` guard on a
  polymorphic `belongs_to` is unnecessary and leaves an order-dependent client API,
  and that the reconstructed side is built from naming conventions only.

### hyper-spec

The largest group, and the one with a common theme: assertions that read
asynchronous client state exactly once, then blame the environment when they lose
the race.

- **`on_client_to` must wait for the value (#64).** It evaluated the block in the
  browser once and matched once. Client state is asynchronous — a value may be
  broadcast, fetched or recomputed after the block first returns — so this raced
  whatever produced it, in the shared DSL rather than in one spec. Now polls,
  mirroring Capybara's own matchers. Positive expectations only: retrying a
  negative would wait for something to stop being true, which is a different
  assertion. Block matchers (`raise_error`, `change`) are excluded, since
  `matches?` is meaningless for them. A matching value still costs exactly one
  evaluation.

- **`on_client_to` must also retry when the client is not ready at all (#64).**
  Polling does not help when the exception comes from *evaluating* the block, which
  escapes before the loop is reached — the "uninitialized constant Physician"
  shape, a load race rather than a wrong answer. Retries on `JavascriptError` too,
  and on timeout re-raises the *last* error so the failure reads as the real
  problem rather than as a mismatch against nil. Only `JavascriptError` is
  retryable: retrying every `StandardError` would swallow real problems and make
  each cost the full timeout.

- **`expect_evaluate_ruby` must wait for the value (#67).** The other read-once
  path. Not hypothetical: `batch6/server_method_spec.rb:71` passed on every cell at
  07:42 and failed on three different cells an hour later, after the runner was
  reconfigured — the spec did not change, the timing did. Deliberately narrower
  than the `on_client_to` fix, because polling re-evaluates the block and a survey
  of the 475 call sites found ~19 whose blocks create/update/destroy/save. The
  first evaluation stays *eager* — Ruby builds the matcher argument before calling
  `.to`, and several specs interpolate a server-side lookup into the matcher that
  depends on the block having already run — so a matching value now costs *zero*
  re-evaluations and those 19 sites behave exactly as before unless they mismatch.

- **Stop asserting exact values the polled block itself mutates (#83).** The
  counterpart hazard. Where a block mutates the very quantity being asserted, every
  retry moves the value one step further from the matcher, so the expectation
  cannot converge *by construction* and the example burns the whole wait before
  failing with a "got" that is really a count of retry iterations —
  `expected: 5, got 44 / 59 / 60`, against a server_method that is literally
  `server_method_count += 1`. A sweep of all 485 call sites found three; each is
  now either idempotent or reads once through `evaluate_promise`, where the promise
  resolution *is* the synchronisation. One further site is flagged and deliberately
  left alone. The hazard is documented in `AsyncExpectationTarget` so the next
  person meets it in the code rather than in CI.

- **A retried example must not lose its isomorphic/mount code (#68, #25).** Two
  independent causes, both fixed. hyper-spec retries every js example, and
  rspec-retry re-runs it in the *same* example-group instance, so instance
  variables survive the failed attempt — but both mount buffers are *consumed* by
  mounting. So the second and third attempts built their page without them: any js
  example that mounts, fails for any reason, and is retried lost everything its
  `isomorphic do` / `before_mount` / `insert_html` / `add_class` calls put on the
  client, and what CI showed was `uninitialized constant <Model>` instead of
  whatever actually went wrong on the first try. Separately, each mount writes its
  payload into a FileCache keyed by the test URL's id — a bare counter starting at
  1 in every process, rooted at a fixed `/tmp` path with no pid, port or run id.
  hyper-model runs 4 concurrent rspec processes in one container and hyper-operation
  3, so two batches reach `/hyper_spec_test/42` and the loser's page boots with the
  winner's client code, invisibly, because the payload is structurally valid. Fixed
  with a per-process token in the key.

- **Injected client code must survive a re-mount (#71, #25).** The same family:
  `before_mount`/`isomorphic`/`insert_html`/`add_class` wrote into pending buffers
  that mounting *drained*, so any later page lost every constant the spec had
  injected — fatal in an `RSpec::Steps` sequence where injection happens once at
  the first step. Drained code now moves into separate de-duplicated *mounted*
  buffers replayed into every subsequently built page. Also replaces
  `evaluate_script('Opal && true') rescue nil` with `opal_loaded?`, which treats
  only a `JavascriptError` as evidence Opal is gone, so a transient WebDriver error
  no longer triggers a page reload that discards client state.

- **`wait_for_ajax` must confirm idle across two polls (#41).** It broke out of its
  loop on the *first* idle observation, so a request starting more than one poll
  interval after the triggering action — behind a debounce, a `requestAnimationFrame`,
  or a `mutate` that re-renders before dispatching — had simply not begun, and
  callers reading state directly got a false "done". Now requires two consecutive
  idle polls. Two guards keep existing callers safe: it stops rather than starting a
  confirmation poll once the deadline is spent (`running?` swallows every exception
  including `Timeout::Error`, and Ruby's `Timeout` fires only once, so a post-swallow
  poll would run unbounded), and a `Timeout::Error` is re-raised only if idle was
  never observed. The deadline uses `CLOCK_MONOTONIC` so Timecop moves do not shift it.

- **`size_window` must not accept a clamped window size (#77).** A blanket
  `rescue StandardError` hid two real bugs: an unknown symbol such as
  `size_window(:medium)` fell through `STD_SIZES` to `symbol + debugger_width`,
  raised `NoMethodError` and silently sized nothing; and `stalled?` accepted any
  size after five polls of *either* dimension holding still, with tallies that
  never reset, so a loaded browser whose resize had not landed read as "the browser
  refuses" and the example ran at the wrong width. Arguments are now validated,
  a full 1.0s of stability in both dimensions is required, the outcome is returned
  as `:reached` / `:stalled` / `:timed_out`, and the rescue is narrowed to
  `Capybara::NotSupportedByDriverError`.

- **Correct for window chrome on BOTH axes (#79).** `resize_to` sets the *outer*
  window; every assertion in the suite is about `innerWidth`/`innerHeight`. Width
  had a correction and height had none, so on any browser with a title bar the
  height comparison could not be satisfied — ask for 768, get 625 — and
  `wait_for_size` never returned `:reached`. Falling through to the "the browser
  will not go further" branch then meant *accepting* whatever size the window
  happened to be, including a resize that had not landed: precisely the failure #77
  removed, reintroduced through the other axis. Every reported stall was short by
  exactly 143 — one constant, on one axis, not a clamp. `determine_size` now
  returns the inner size the caller asked for and the correction is applied at the
  resize, so what is waited for and what was asked for are the same numbers. The
  chrome is measured as outer *minus inner*, not "what we asked for" minus inner,
  so a window manager with a minimum height cannot have us bake its clamp into
  every later resize.

- **Bracket the TimeCop clock assertions instead of guessing a tolerance (#63).**
  The specs compared a fresh browser round trip against a once-measured clock
  offset, with tolerances of 1, 3, 3 and 1 for the same shape of assertion and no
  stated reason for the difference; the effective error was "how much slower is
  this round trip than the one that measured the gap", unbounded under load. Every
  guessed tolerance is replaced by a bracket: sample the server clock either side
  of the round trip and require the client's timestamp to fall inside the window
  the server observed around it, so a slow round trip widens the window by exactly
  as much as it delays the read. `@sync_gap` becomes a range rather than a point,
  for the same reason. Two tolerances that were expressed in *scaled* seconds
  inside `Timecop.scale 60` — really latency budgets of ~83ms and ~167ms — are
  fixed with it, and the frozen-time example now applies the offset like its three
  siblings. Verified by simulation: the bracket passes for a correct clock across
  round trips from 0.2s to 5s and with a real 30s offset, and fails a client skewed
  by 10s or 30s, so it is not merely a wider window. A follow-up widens the bracket
  by `2 × scale` under `Timecop.scale`, where the server clock runs n× real time
  while the browser advances its own copy at real speed between syncs.

- **Give every registered driver a read timeout (#74).** Capybara's
  `default_max_wait_time` bounds only *re-running* a finder, not a single WebDriver
  command that never returns, and Selenium ≤ 4.46 registers no default HTTP client
  timeouts — so a wedged browser hung until the OS TCP timeout (~14 minutes
  observed), times rspec-retry's three attempts, holding a runner ~42 minutes.
  `DriverTimeouts.bound!` re-registers each driver to fill in an HTTP client with
  open 30s and read 90s (or 300s for a cold Sprockets compile), overridable via
  `HYPER_SPEC_READ_TIMEOUT` / `HYPER_SPEC_OPEN_TIMEOUT`, where 0 means "impose
  nothing".

- **Filter both Ruby 3.4 chilled-string warnings (#19, #91).** The filter matched
  only the `Symbol#to_s` form and not the `literal string will be frozen` one,
  which is the flood: a single hyper-model job carries 1727 of them in a 2454-line
  trace — 70% of the log — 892 from em-websocket's `framing07.rb`, 821 from its
  `masking04.rb`. Widened, with the path guard unchanged so nothing from Hyperstack
  or user code is newly suppressed, and half the new spec's examples negative,
  because a filter that is too wide is a worse bug than one that is too narrow.

- **Assert the running cell matches `supported_versions.yml` (#51).**
  `rake hyperstack:matrix:check` only proves the table and the CI cell list name
  the same cells; nothing proved a cell actually *runs* what it advertises. This
  reads the running system — Ruby, Rails, Opal and react-rails from loaded
  constants, and React from `window.React.version` in the browser, the only
  authority for an axis the table itself documents as derived. Each axis skips
  rather than errors when its constant is absent, and the whole file skips when
  `HYPERSTACK_CELL` is unset.

- **Pin selenium-webdriver to a minor series (#84).** It was unpinned, and it
  drives the browser for every js spec in every gem, so an upstream release
  changed what the whole suite ran against, silently, between two pipelines on the
  same commit — 4.47.0 at 13:44 and 4.48.0 at 20:49 on identical content. A red
  pipeline should mean the code changed, not that a dependency did. Pinned to
  `~> 4.48.0`, the series CI already runs; the `.0` is deliberate, since `~> 4.48`
  would permit 4.49 and float again. This narrows the window rather than closing
  it — Chrome for Testing in the cell image still moves independently.

- **One dead browser must not fail the whole batch at teardown (#113).** When
  Chrome dies mid-run, the session is gone before the next
  `Capybara.reset_sessions!` — which then raised `InvalidSessionIdError` from an
  `after` hook, failing the *current* example and, because the poisoned session
  stayed in Capybara's pool, every example after it in the same process. One crash
  was therefore reported as an entire batch: `hyper-operation:part2` at 155
  examples / 122 failures, `hyper-model batch4` at 30 / 29, with 431 `tab crashed`
  markers in a single trace. Those were not 122 problems; they were one crash and
  121 teardowns tripping over the corpse. #56 is the precedent — 268
  `InvalidSessionIdError`s among which only 2 of 69 reported failures were
  genuine. The dead session is now dropped rather than propagated, and Capybara
  lazily builds a fresh one for the next example. It does not hide the crash: the
  example that was running when the browser died still fails, and the reason is
  warned to stderr. The permitted list is deliberately short
  (`InvalidSessionIdError`, `NoSuchDriverError`, `NoSuchWindowError`,
  `ECONNREFUSED`, `EOFError`) and explicitly *not* `WebDriverError` — a blanket
  rescue here would swallow real driver faults, the mistake #77 documented in this
  same file. Clearing the pool is itself rescued, since raising out of an `after`
  hook would be worse than the problem being fixed.

  The amplification also made retries far more expensive than the underlying fault
  warranted: a retry re-runs the whole job rather than the one example that broke,
  so a single early crash forfeited a ~12-minute job. Tag pipeline 6900 spent 249
  attempts across 121 jobs, 77 of them failed, every one eventually passing on
  identical code.

  Confirmed against real crashes rather than only against stubs — the pipeline
  that shipped it recorded live recoveries from both `EOFError` and
  `InvalidSessionIdError`, and carried on.

- **Register the Pry code-capture hook only once (#113).** `require` keys on the
  resolved path, so reaching `hyper-spec.rb` by a second path re-ran the
  registration and raised `ArgumentError: Hook with name 'hyper_spec_code_capture'
  already defined!`. Latent since the hook was introduced and unrelated to the
  dead-session work above, which merely exposed it; now guarded with
  `hook_exists?`.

### hyper-i18n

- **Guard the async Store writes in `t` / `t_async` / `l` (#42).** The three wrote
  to `Store.translations` / `Store.localizations` inside the `.then` callback of
  the `Translate`/`Localize` operation, so the earlier synchronous guard at call
  time could not protect them: if the Store was still uninitialized when the
  promise resolved, the write raised `undefined method 'translations' for nil`
  inside a promise chain where nothing catches it. Replaced by
  `cache_translation` / `cache_localization` helpers that bail out when the store
  accessor returns nil and skip the cache update rather than exploding.

### hyperstack-config

- **`js_import` checked every package against the same global key.** The
  "package not found" guard was written `` `Opal.global['#{name}'] === undefined` ``,
  and Opal does not interpolate `#{}` inside a quoted subscript in a backtick, so
  it compiled to the literal `Opal.global['name']`. In a browser this is invisible
  — `window.name` always exists, so the guard passed vacuously — but under V8
  prerendering `globalThis.name` is undefined, so it raised "The package X was not
  found" for the first package every time, which is why prerendering has been
  stuck off. Fixed by dropping the quotes. The new spec asserts against the
  *compiled* JavaScript, since no browser test can reach the bug.

### rails-hyperstack (the install generator)

- **The generated app's React bundle is minified: 1.26 MB → 421 KB (#107).** The
  most user-visible change in this release. `esbuild.config.js` set
  `NODE_ENV=production` — so React's development branches were already folding
  away, this was never a dev build — but never set `minify`, so the bundle shipped
  with full identifiers, comments and whitespace. esbuild flagged its own output
  on every build (`react_runtime.js 1.2mb ⚠️`) and nothing acted on it.

  This is not a test fixture: `hyperstack:install` writes `react_runtime.js` into
  the app, adds `//= link_tree ../builds` so sprockets serves it, and injects
  `//= require react_runtime` into `application.js` ahead of `hyperstack-loader`
  — which the layout loads on **every page**. Sprockets does not compress
  JavaScript by default and nothing sets `config.assets.js_compressor`, so what
  esbuild emitted was what every browser received.

  Measured against react 19.2 rather than estimated:

  ```
  unminified   1,260,648 bytes   (gzip 211,184)
  minified       421,272 bytes   (gzip 130,222)
  ```

  −67% raw, −38% on the wire. Tied to the same `NODE_ENV` signal as `define`, so
  `NODE_ENV=development` still produces a readable bundle.

  One spec changed with it. `component_spec.rb`'s `componentDidCatch` example
  matched the React >= 17 componentStack against
  `/ErrorFoo|at eval|factory\.js/`, and the alternative that actually matched was
  `factory.js` — create-react-class's path surviving in the *unminified* output
  (2 occurrences unminified, 0 minified). None of the three ever named a
  Hyperstack component; React >= 17 frames name the JavaScript function the
  engine sees, which is create-react-class's internal constructor. That is what
  the comment above the assertion already said — "native error frames, which name
  files rather than components" — so the regex was contradicting its own
  documentation and re-encoding how the bundle happened to be built. It is
  removed; the non-empty-`componentStack` check above it is the real contract and
  remains, as does the exact component-by-component assertion for React <= 16,
  where the synthetic stack genuinely does name components.

  Not addressed here, and now measured: `react-dom/server` is bundled into the
  *client* runtime despite a dedicated `react_server_runtime.js` entrypoint
  existing for prerendering. It is 189,490 bytes — 45% of what remains after
  minification — but it backs a documented API (`Hyperstack::Component::Server.render_to_string`),
  so removing it is a public API change rather than a size fix. Tracked in #109,
  with the caching question in #108.

- **Split the JS pipeline into per-version generator strategies (#51).**
  `install_webpack` unconditionally ran `rails webpacker:install`, which does not
  exist on Rails 7. Unlike the other Rails 7.2 failures this cannot be a capability
  check, because the two pipelines scaffold *different applications* — Webpacker
  for Rails < 7, esbuild + jsbundling for Rails >= 7. The divergent ~20% is
  extracted into `JsPipeline::Webpacker` and `JsPipeline::Esbuild`, selected by
  `HYPERSTACK_JS_PIPELINE` or Rails major; routes, initializer, manifests and
  component generation stay shared. The strategies are nested under
  `Rails::Generators`, not `Hyperstack` — a partial `Hyperstack` constant at
  generator-load time broke boot with a `Logger` NameError.

- **Make the test-app harness pipeline-aware, and declare the pipeline per cell
  (#51).** The Rails 7.2 cell still died on `Unrecognized command
  "webpacker:install"`, but from `spec:prepare`, which calls Webpacker directly
  *before* the generator ever runs. The Rakefile now branches the same way, with
  `spring stop || true` on the esbuild path because Rails 7 apps ship no spring and
  exit 127 must not abort. Each cell now *declares* `HYPERSTACK_JS_PIPELINE` rather
  than relying on inference from the ambient rails gem.

- **Add `javascript_include_tag` to the generated layout (#51, #52).** On Rails 7+
  the installer runs `rails new --skip-javascript`, and that layout ships no
  javascript tag at all; the only fallback anchored on `javascript_pack_tag`, which
  exists solely in Webpacker apps. So the sprockets `application` bundle — and with
  it Opal and the entire Hyperstack client — was never loaded, and `/` rendered
  blank. Now injected before `</head>`, guarded by a scan for an existing tag so it
  is a no-op on Rails 6.1 and idempotent on re-install.

- **Ignore Rails 7+ built-in routes in `new_rails_app?` (#51).** It decides whether
  to generate the top-level `App` component by counting non-blank, non-comment,
  non-`mount` lines in `config/routes.rb` and treating ≤ 2 as a fresh app. Rails 7+
  ships built-in routes there (`/up`, plus 7.2's PWA service-worker and manifest
  routes), pushing a brand-new app over the threshold — so the installer logged
  "Top Level App Component skipped" and never created `App` or its `hyperstack#app`
  route. Framework-owned `rails/` routes are now skipped.

- **Port the branch-only generator fixes to edge (#98).**
  `install_mui_generator` and `install_bootstrap_generator` hardcoded the Webpacker
  answer — appending to pack manifests and running `bin/webpack` — which silently
  did nothing on an esbuild app, leaving `Mui`/`BS` undefined at render time. They
  now extend the pipeline strategy and call a three-method surface
  (`expose_npm_global`, `add_npm_stylesheet`, `build_js_bundle`) implemented in
  both. Separately, `hyperstack_generator_base.rb` only injected
  `javascript_include_tag` *after* an existing `javascript_pack_tag`, so Rails 7
  apps got nothing and a warning; it now falls back to injecting before `</head>`.

- **Make the post-install asset advice pipeline-aware (#98).** The last hardcoded
  Webpacker answer in the installer, and the one the user actually reads: on
  finishing, `hyperstack:install` printed *"Webpack integrated with Hyperstack.
  Add javascript assets to app/javascript/packs/client_only.js and
  /client_and_server.js"* unconditionally — so every Rails 7+ install, meaning
  every esbuild app, was pointed at two pack manifests esbuild never reads.
  `js_assets_advice` joins the strategy surface, and the esbuild one names
  `react_runtime.js` / `react_server_runtime.js` and `yarn build` instead.

- **Unit specs for the install generator's decision logic (#51).** 17 fast
  examples, no app or browser boot (~0.05s total), pinning the two bugs above
  against real Rails 6.1 and 7.2 `routes.rb` fixtures plus the JS-pipeline strategy
  dispatch — including that an unknown `HYPERSTACK_JS_PIPELINE` raises rather than
  silently defaulting.

### Dependency declarations

- **Widen the rails and react-rails caps to the matrix span (#20).**
  `supported_versions.yml` claims rails 6.1–8.1 and react-rails 2.6–3.3 and CI runs
  a green cell for each, but with no cell env set — exactly how `rake publish`
  builds — the gemspecs resolved to `rails >= 5.0.0, < 7.0` and
  `react-rails >= 2.4.0, < 2.7.0`, so the *published* gem refused to install on the
  Rails 7.2 and 8.x it is tested against. An installed gem carries the serialized
  spec, so the narrow default is what shipped. `hyperstack:matrix:check` guarded
  table-vs-CI; nothing guarded table-vs-gemspec, which is how the two drifted.
  Widened in all 12 gemspecs (rails `< 9.0`, react-rails `< 4.0`; lower bounds
  untouched). Because widening a default changes what a cell resolves when it does
  not pin, the five cells that were reaching their versions *through* the old
  narrow defaults now pin both axes explicitly — without that, the widening would
  have floated all four rails61 cells onto Rails 8.1 and both react16 cells onto
  react-rails 3.3, silently turning the matrix into several copies of one
  configuration. Not fixed here: `rails-hyperstack` still declares runtime
  `opal-rails ~> 2.0`, which is hard-capped at `rails < 7.3`, so a default-built
  gem is still held below Rails 8 by that dependency rather than by a cap. What a
  single published gem should depend on is #37.

- **Every version axis is selectable, and a blank selector means unset (#51, #78).**
  react-rails, opal and rails became ENV-selectable so a cell can move an axis. The
  old `ENV[x] || 'a', 'b'` idiom could not do it: the trailing constraint survives
  when the variable is set, so `RAILS_VERSION='~> 7.2'` resolved to
  `['~> 7.2', '< 7.0']` and installed nothing. The variable now replaces the whole
  requirement. Separately, `''` is truthy in Ruby, so an empty selector produced
  the requirement `['']` and aborted `bundle install` with "Illformed requirement"
  from inside a gemspec, pointing nowhere near the cell that caused it — and
  `rake hyperstack:cell:env` maps a YAML nil to `""`, so a cell written
  `RAILS_VERSION: ""` (or with a bare key) did exactly that. All 56 call sites
  across 12 gemspecs now go through `Hyperstack.version_selector`, which treats
  blank or whitespace as unset; no gemspec reads ENV directly any more, and the
  three hand-rolled blank guards in the Dockerfile are gone. 132 examples cover it,
  each evaluating a gemspec in a *subprocess* because `Gem::Specification.load`
  memoises per path and every ENV-varying example would otherwise pass vacuously.

- **Declare `opal ~> 1.8` (#51).** The gemspecs declared `>= 0.11.0, < 2.0` — a
  claim back to Opal 0.11 that nothing tests — while every line has actually run
  1.8.3 for a long time. The matrix exists so that declared support and tested
  support are the same thing.

- **Pin `pg` below its next major, behind a `PG_VERSION` selector (#102).** `pg`
  drives the database the specs actually run against and was unpinned in
  hyper-model and hyper-operation, so a new major could arrive with no commit of
  ours — and it would arrive on cells running EOL Rails 6.1, whose
  `postgresql_adapter` calls `PG::Coder.new` with a positional Hash. That has been
  deprecated in `pg` since 1.5.0 and fixed in Rails 7.2+, never in 6.1, so the
  major that finishes the deprecation turns a warning into a failure on exactly
  the cells that cannot be fixed. Capped at `< 2`, with `PG_VERSION` plumbed
  through the gemspecs, `supported_versions.yml` and the cell-image build the way
  `SQLITE3_VERSION` already is, so moving it per cell stays a one-line change. No
  cell sets it today.

- **Pin sprockets below 4.2 everywhere it was still unbounded.** sprockets >= 4.2
  raises "can't modify immutable cached environment" and stops compiling the Opal
  assets, and nothing says so at the point of failure — the browser simply reports
  "Opal is not defined" and every mount dies inside the Opal runtime. Nine of the
  ten components already carried the pin; `hyperstack-config`'s Gemfile and, worse,
  the `sprockets "~> 4.0"` that `spec:prepare` appends to the *generated* app's
  Gemfile on the Rails 8 branch did not — so the one app built from scratch, for
  the newest cells, was the one resolving sprockets unbounded. Found while rebasing
  the branch lines onto edge.

- **Pin `opal-rails ~> 2.0`, and make it selectable.** It was unconstrained in 11
  gemspecs while the latest is 3.0.0, so simply setting `RAILS_VERSION` would have
  silently jumped the asset pipeline from opal-rails 2 to 3 as well — an `app/opal`
  rewrite (#37), not a version bump.

### CI and tooling

- **One gem list, two consumers — and the CI publish path is gated on it (#49).**
  `rake publish` and the eleven `*-deploy` jobs already shared one
  *implementation* (`publish_gem`), but not one *list*: the Rakefile hardcoded its
  own eleven gems and `.gitlab-ci.yml` hardcoded the same eleven as `COMPONENT`
  values. They agreed by care rather than construction, and nothing would have
  noticed when they stopped — add a gem and forget the deploy job and it silently
  never ships. `PUBLISHED_GEMS` is now the list and `rake hyperstack:gem:check`
  asserts the pipeline matches it, the same "one table, two consumers" rule
  `supported_versions.yml` follows for cells (#51). It also catches the case a
  list-vs-list comparison misses: a gemspec on disk that is in neither list, which
  would ship to nobody with nothing to complain. `hyper-console` is *named* as the
  one deliberate exclusion (#86) so "excluded on purpose" and "someone forgot"
  cannot look alike.

  The check runs in `supported-versions`, not on the deploy jobs — those are
  `when: manual` and `allow_failure: true`, so a check there would only run when
  someone starts a deploy and could not fail the pipeline when it did. That also
  closes the asymmetry that prompted this: publishing *locally* had always gated
  on `matrix:check`, while publishing through CI — the path that actually ships —
  gated on nothing.

- **`RELEASE-PROCESS.md` no longer claims the tag publishes the gems.** It said
  *"once build passes gems will be released!!!"*. It does not: the eleven
  `*-deploy` jobs are `when: manual`, so pushing the tag starts a pipeline and
  publishes nothing until someone starts each one. They are also
  `allow_failure: true`, so a publish that fails leaves the pipeline green —
  which is now its own step, because it is the failure that would go unnoticed,
  and it is not hypothetical: #49 fixed a publish path that stored the multipart
  form envelope *as the gem* while the registry answered `201`. The document also
  now records what the deploy job actually does — publish, then poll the packages
  API until the version reports status `default` — and that
  `resource_group: production` serialises them.

- **Recover the test coverage stranded on the retired branch lines.** A
  content-level diff of `rails-7`, `rails-8.0` and `rails-8.1` against `edge`
  — file contents, not commit SHAs, since those lines were linear rebases and
  SHAs cannot answer the question — found no unmerged library code: every fix on
  them is here, and in places this line supersedes them (#81/#92/#93 sanitize at
  the JSON boundary where `rails-8.1` monkey-patched `Column#as_json`; #83 and
  #98 exist only here). What *was* stranded is coverage for code `edge` already
  ships. `hyper-component` gains `react18_spec.rb`, 8 examples for the React 18
  `createRoot` rewrite (#18) — its `lib` was byte-identical to `rails-8.1`, and
  no spec on this line so much as mentioned `createRoot`, so that code shipped
  untested — and the #39 transient-error example, whose fix was already here
  without a test. `rails-hyperstack` gains real reactive-push assertions and a
  server-side-create example exercising the #44 queued path end to end, plus a
  `DatabaseCleaner.clean` at the start of each `js` attempt so a retry does not
  begin dirty. `run-local-docker-specs.sh` builds the esbuild bundles in a node
  container before the Opal precompile.

  Two of these failed on first contact with the full matrix, which is the point:
  each had only ever run on the single cell its branch line tested. The
  `set_state!` example was asserting React 18's coalesced render count on React
  16/17 — and, being written with a polling matcher over a block that mutates
  the counter it asserts, reported the retry count rather than the real answer
  (#83, again). The other found #103, above.

- **Prebaked per-cell dependency images (#57, #73, #75).** Restoring the gem cache
  cost a measured 57.9s per job — about 46 minutes over a 48-job pipeline —
  against a warm `bundle install` of 8.9s. Each cell now has an image with its
  `local_gems` bundle baked in, including compiled native extensions, and the gem
  cache is dropped entirely. `prepare-context.sh` stages only Gemfiles, gemspecs
  and the `version.rb` files the gemspecs require, so the `COPY` layer is
  invalidated by dependency changes rather than by every commit, and the build
  derives its args from `rake hyperstack:cell:env` so image and test run share one
  source of truth. Each `before_script` hard-fails if the prebaked marker is
  absent, so a cold fallback cannot masquerade as a slow success. A new `images`
  stage ordered before `test` stops a job starting against an image still being
  built in the same pipeline.
  Two follow-ups closed the remaining gaps: `spec:prepare` shells out under
  `Bundler.with_unbundled_env` and runs plain `gem install`, so those gems land in
  `GEM_HOME` and never in `local_gems` — which is why nokogiri recompiled from
  source (78s → 202s) on every job even with the cache warm. Those pins move into
  `spec_prepare_gems.rb`, read by both `spec:prepare` and the image build so they
  cannot drift, and are baked in (#73). Then the ~76-gem bundle `rails new`
  installs and the npm tree `webpacker:install` downloads are warmed the same way
  by scaffolding and discarding a throwaway app in a late layer (#75) — the npm
  half being pure waste, because `cache: []` on the test jobs *replaces*
  `default:`'s list rather than merging, so the `yarn-v1` cache never applied.
  Roughly 200s off each rails61 cell from #73 and ~95s more from #75.

- **Retry the registry login in `build-cell-image` (#94).** A transient TCP reset
  from the registry's JWT auth endpoint failed the job 66s in; a manual retry
  passed 63 seconds later. The job is `allow_failure: true`, which is what makes
  this worth fixing rather than retrying by hand: an unretried reset does not turn
  the pipeline red, it leaves that cell testing against the *previous* image, with
  the older `supported_versions.yml` baked in — precisely the drift the job's
  rules exist to prevent, reintroduced by a network blip. Three attempts with a
  5s/10s backoff. A job-level `retry:` would not do, since reaching this failure
  means retrying `script_failure`.

- **Keep the generated app's log when a test job fails (#81).** Chasing the Rails
  8.1 breakage cost several full-matrix runs because this did not exist: the
  browser reported 79 HTTP 500s and 1774 client-side errors, and there was not one
  backtrace anywhere to say what raised. The client-side symptom is in the job
  trace; the server-side cause never is. Added to both job templates,
  `when: on_failure`, `expire_in: 1 week`.

- **Cache keys, and caching on failure (#55).** The gem cache key gains
  `$HYPERSTACK_CELL`, because `local_gems` holds compiled C extensions and each
  cell deliberately installs a different set, so cross-cell restores were invalid.
  `YARN_CACHE_FOLDER` moves under the project dir and is shared under one key —
  npm packages do not vary by cell and the cache is content-addressed, so one entry
  warms every job instead of ~48 near-identical copies. And both caches gain
  `when: always`: GitLab's default is `on_success`, so a failing job never uploaded
  its cache and every red iteration re-installed from scratch (~219s versus ~90s
  warm).

- **Stop retrying `script_failure` (#56).** A job-level retry was added for
  environmental flakes and then narrowed two commits later, because its
  justification was a misdiagnosis: the real cause was the runner filling its disk,
  which killed Chrome and produced 268 `InvalidSessionIdError`s — only 2 of 69
  reported failures were genuine. With that fixed in infrastructure, retrying
  `script_failure` only hides real test failures. `runner_system_failure` and
  `stuck_or_timeout_failure` are kept, since they are never the code's fault.

- **Stream Ruby output live (#69).** `$stdout`/`$stderr` default to `sync = false`
  whenever stdout is not a tty, which is every CI job, so Ruby's own buffer held
  output until ~8KB or process exit and a progressing run looked hung for minutes.
  `stdbuf` does *not* fix this — it shims glibc's `setvbuf`, and MRI's IO does not
  go through glibc's buffered stdio; measured here before committing. Set in the
  10 spec_helpers rather than inside hyper-spec's lib, since a shipped gem should
  not mutate global IO state as a side effect of `require`.

- **Delete the dead Travis config (#54).** 12 tracked `.travis.yml` files, the
  commented-out Travis `deploy:` block carrying an encrypted RubyGems `secure:`
  blob, the two now-unreferenced gemfiles those configs pinned in place, and three
  dead build badges. Note that deleting the file does not close the credential
  exposure — it stays in git history; revoking the key is the only thing that does.
  Deliberately untouched: `DRIVER=travis`, which is unrelated to Travis CI and
  selects hyper-spec's Capybara profile.

- **Publish gems to the GitLab RubyGems registry (#49).** `gems.ru.aegean.gr` was
  repointed and geminabox retired, breaking both publish paths: `rake publish` used
  `curl -F` multipart, so GitLab answered 201 and then stored the *form envelope*
  as the gem, and the CI deploy script had Ruby string interpolation pasted into
  bash and pushed a literally-named file. A single `publish_gem` helper now POSTs
  the gem as a raw octet-stream and then polls the packages API until the version
  reports status `default`, because 201 only means the file was stored.
  Credentials fall back through `GEM_SERVER_TOKEN` → `BUNDLE_GEMS__RU__AEGEAN__GR`
  → `GEM_SERVER_KEY` using `find { !v.to_s.empty? }` rather than `||`, since an
  empty CI variable is truthy in Ruby.

- **The matrix machinery itself (#51).** `supported_versions.yml` is the single
  source of truth, with `rake hyperstack:matrix:check` asserting that every cell in
  the table appears as a `HYPERSTACK_CELL` in the pipeline and vice versa (also a
  `publish` prerequisite), `rake hyperstack:cell:env` resolving a cell's
  environment, and CI naming cells rather than values so the two cannot drift.
  All three file reads pass `encoding: 'UTF-8'` explicitly — the runners set no
  locale, so Ruby defaults to US-ASCII and the em-dashes in the comments raised
  `ArgumentError: invalid byte sequence in US-ASCII`, including in the runtime read
  that any app booting without a locale would have hit.

- **The Rails 8 corner is a complete 2×2 grid (#38, #80).** The matrix ran Ruby 4.0
  only on Rails 8.0 and Rails 8.1 only on Ruby 3.4, so the intersection — the
  combination a user on the newest supported Rails *and* the newest Ruby is on, and
  the configuration #38's client-runtime failures were reported against — was never
  run, and `SupportedVersions` classified it `:untested`. With
  `rails81-react19-ruby40` added, every comparison across the Rails 8 corner moves
  exactly one axis again.

- **A Rails 7.2 + React 19 cell (#95).** The one hole a shipped gem line fell
  through: Rails 7.2 was tested only with React 16.14, and React 19 only with Rails
  6.1/8.0/8.1 — while the `rails-hyperstack` version ru/hyperstack-addons depends
  on is exactly Rails 7.2 + React 19. Also adds
  `docs/development-workflow/ci-matrix.md`.

- **Halve the parallel rspec processes on the heaviest jobs (#113).** The browser
  crashes that #113's teardown fix stops *amplifying* were themselves caused by
  the kernel OOM-killer: containers exit with code 137 (SIGKILL), and no runner
  block sets `memory` or `memory_swap`, so the containers are unbounded and the
  kernel picks an arbitrary victim — usually Chrome. Ruled out along the way: no
  per-container CPU limit is configured, `--disable-dev-shm-usage` is already
  passed so `/dev/shm` is not the constraint, and no trace carries an `ENOSPC`.
  The ceiling is RAM, not cores. `PARALLEL_PROCESSES` drops 4 → 2 on hyper-model
  and 3 → 2 on `hyper-operation:part2`, the two jobs that ran the most browsers at
  once. This buys headroom rather than a guarantee; a memory limit on the runner
  registrations is the actual fix and belongs to infrastructure.

- **Documentation.** `docs/development-workflow/ci-matrix.md` describes the matrix
  and how to add a cell; the prebaked-image work is recorded job by job (#57).

## 1.0.alpha1.8.34.18.61.1614.6 — 2026-07-02

### Bug fixes

- **hyper-model: `convert_integer` returns `nil` for blank/non-numeric integer
  input instead of raising `FloatDomainError: NaN` (#34).** `convert_integer`
  did `Integer(parseInt(val))`; `parseInt` returns JS `NaN` for empty/blanked/
  non-numeric input and `Integer(NaN)` then raises `FloatDomainError: NaN`
  (surfaced in the browser console as `Uncaught Error: NaN`). It now guards the
  `NaN` case and converts to `nil`, matching how ActiveRecord coerces `""` on an
  integer column and mirroring `convert_float`, which already tolerated these
  inputs. `convert_bigint` is aliased to `convert_integer`, so it is fixed too.
  Adds a `column_types` browser spec asserting blank / `"abc"` / `nil` integer
  input converts to `nil` with no console error.

- **hyper-model: broadcast `integrity_check` no longer false-positives on
  UTC-vs-local datetime serialization (#33).** `integrity_check` compared the
  raw serialized strings from the broadcast `record` and `previous_changes`
  (`@record[attr] == value.last`), so a datetime serialized as UTC on one side
  and local-offset on the other — the same instant, e.g.
  `2021-12-17T00:00:00.000Z` vs `2021-12-17T02:00:00.000+02:00` — failed the
  equality check and raised a spurious `Broadcast Integrity Error`, rejecting
  the save's broadcast client-side. It now compares normalized values via
  `@backing_record.convert(attr, …)` on both sides, mirroring the existing
  `value_changed?` check; `convert`'s guards leave associations, foreign keys
  and `nil`s untouched, so two representations of the same moment compare equal
  regardless of `default_timezone` / `time_zone_aware_attributes`.

### CI / tooling

- **Update the CI test jobs to Bundler `~> 4.0` (#36).** The browser-spec job
  templates previously ran `bundle install` with the base image's default
  Bundler and no explicit pin; they now `gem install bundler -v '~> 4.0'` first.
  Applied on the `edge` line first (full suite green on Rails 6.1 / Ruby 3.4)
  ahead of propagating to the `rails-7` line.

## 1.0.alpha1.8.34.18.61.1614.5 — 2026-07-01

### Bug fixes

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

## 1.0.alpha1.8.34.18.61.1614.4 — 2026-06-29

### Features

- **Auto-boot the client hot reloader on import; add hot-reload docs + specs
  (#30).** Importing `hyperstack/hotloader` only defined the class — nothing ever
  called `Hyperstack::Hotloader.listen`, so the browser never opened the websocket
  and hot reload silently did nothing in a fresh app (the explicit
  `OpalHotReloader.listen` boot was lost in the hyperloop → hyperstack
  import-system refactor, last seen in `90a3c7dc4`). `hotloader.rb` now adds
  `self.boot!`, invoked at file scope, which calls `listen` automatically when the
  client bundle loads. It is guarded to run only in a real browser
  (`window`/`document`/`WebSocket` present), so it is a no-op during prerendering
  and on the Rails server; it reads port/ping from the `Hyperstack.hotloader.*` JS
  config and defers via `setTimeout` so the rest of the bundle loads first. The
  `listen` hyper-component touchpoints are now guarded so the hot loader also works
  in a minimal bundle that does not pull in hyper-component. Adds
  `hotloader_server_spec` (deterministic server-side message building) and
  `hotloader_client_spec` (`js:true`; proves the client auto-connects on page load
  and evaluates code pushed from the server), and a new
  `docs/rails-installation/hot-reloading.md` linked from `SUMMARY`.

### Bug fixes

- **Fix hyper-model `Collection#_count_internal` returning raw JS `undefined`
  (#31).** Under Opal 1.8.3 / Ruby 3.4 an unloaded `ReactiveRecord::Collection`
  could have its count resolve to raw JS `undefined`, so callers such as `empty?`
  (`count.zero?`) and the ancestor check in `sync_collection_with_parent` crashed
  on first render with `Uncaught TypeError: Cannot read properties of undefined
  (reading '$zero?')`. `_count_internal` now captures the computed count and
  coerces `undefined`/`nil` to `0` before returning, so every caller gets a value
  that safely answers `zero?`. All existing behavior for defined values and the
  `load_from_db` side effects / `@count = 1` fallback is preserved. Adds batch2
  regression specs covering both the `_count_internal` → 0 coercion and `empty?`
  not crashing when the count is undefined.

## 1.0.alpha1.8.34.18.61.1614.3 — 2026-06-27

### Bug fixes

- **Fix Opal 1.8 props/state *nested* hashes still returning truthy values for
  missing keys (#26, follow-up to #24).** The #24 fix copied the top-level native
  props/state object into a plain object literal so `Hash.new` took its populate
  branch — but only at the top level. Any **nested** Ruby Hash param arrives as a
  Map-backed Opal Hash and is rebuilt via `Hash.new(map)`, which hits a different
  bug: the `native` stdlib's `Hash#initialize` populates from a `Map` but forgets
  to `return self`, so it falls through to MRI `Hash#initialize` and sets the
  source Map as the hash's **default value**. Missing nested keys
  (`columns[:x][:filter]`, etc.) then returned the whole nested hash instead of
  `nil` — the actual root cause behind the hyperstack-addons `Pager`
  `to_sym for nil` crash. hyper-component now patches `Hash#initialize` (in
  `native_to_hash.rb`) to clear the leaked default after a Map-sourced
  construction, fixing every `Hash.new(opal_hash)` path (props, state, and
  re-render `incoming` props) recursively. Regression specs added in
  `spec/client_features/native_to_hash_spec.rb`.

  This is a workaround for an upstream Opal bug; a ready-to-file patch and a
  Hyperstack-free reproduction spec for the Opal repo live in
  `ruby/hyper-component/upstream/opal-native-hash-new-from-map/`.

- **Fix flaky aliased attribute methods (#25, !30).** `ReactiveRecord#method_missing`
  matched the raw method name against real columns, so an aliased attribute method
  (e.g. `surname_changed?`, alias of `last_name`) dealiased to no column and had no
  lazy fallback — it relied on `alias_attribute`'s generated alias having already
  propagated to the live browser session, which raced under CI load (`undefined
  method 'surname_changed?'`, flaky `alias_attribute_spec.rb:81`). `method_missing`
  now strips the `=`/`!`/`?`/`_changed?` suffix, dealiases the base via
  `_attribute_aliases` (walking superclasses for inherited aliases), and matches
  that against columns, so aliased accessors and dirty-tracking methods resolve
  deterministically. Only fires when the original lookup found nothing and the name
  dealiases to a real column, so non-alias paths are byte-for-byte unchanged.

## 1.0.alpha1.8.34.18.61.1614.2 — 2026-06-26

### Bug fixes

- **Fix Opal 1.8 props/state hashes returning truthy values for missing keys
  (#24).** hyper-component wrapped native React props/state objects with
  `Hash.new(native)`, relying on the `native` stdlib reopening `Hash#initialize`
  to populate the hash from the JS object's keys. Under Opal 1.8 that override
  only takes its populate branch when the native object's constructor is
  `Object`/`undefined` (or it is a `Map`); React's props/state objects no longer
  match, so the core MRI `Hash#initialize` ran instead — setting the hash's
  *default value* to the native object and leaving the hash empty. Any missing
  key (`contents[:filter]`, etc.) then returned the truthy native object rather
  than `nil`, silently corrupting absent-key checks (e.g. hyperstack-addons
  `Pager#filters` selecting every column, leading to the downstream
  `to_sym for nil` crash). New `Hyperstack::Internal::Component.native_to_hash`
  copies the native object's own enumerable properties into a plain object
  literal before `Hash.new`, forcing the `native` bridge's populate branch so the
  result is a real Hash with a `nil` default and the same recursive key
  conversion as before. Applied at all five wrap sites (`element.rb`,
  `instance_methods.rb`, `should_component_update.rb` ×2, `class_methods.rb`).
  Follow-up to #23.

## 1.0.alpha1.8.34.18.61.1614.1 — 2026-06-26

### Versioning

- **Adopt the `hyperstack-addons` compatibility scheme**, keeping the historical
  `1.0.alpha1.8` prefix:
  `1.0.alpha1.8.<ruby>.<opal>.<rails>.<react major+minor>.<patch>`. The previous
  `1.0.alpha1.8.34.18.0` marker becomes `1.0.alpha1.8.34.18.61.1614.1` =>
  Ruby 3.4, Opal 1.8, Rails 6.1, React 16.14, patch 1. This makes the full
  compatibility matrix explicit in the version and keeps this repo aligned with
  the downstream `hyperstack-addons` gem (`34.18.61.1614.0`). The trailing
  `.1` is this fix. All per-gem `version.rb` files, `HYPERSTACK_VERSION`, and the
  component `Gemfile.lock`s move to the new string in lockstep.

### Bug fixes

- **Fix client components crashing under Opal 1.8 / Rails 6.1 (#23).** With Opal
  1.8.3, model class load reaches `ClassMethods#method_missing` for server-only
  macros such as `:regulate_scope` *before* the first mount. The generic
  attribute-accessor heuristic matched the macro name and prematurely called
  `define_attribute_methods`, while `ReactiveRecord::Base.public_columns_hash`
  was still `nil` — producing `undefined method '[]' for nil` in `columns_hash`
  and then the cascading `<Pager>` `to_sym for nil` render crash. Two changes in
  `reactive_record/active_record/class_methods.rb`:
  - **Root cause:** exclude `SERVER_METHODS` from the `method_missing`
    attribute-defining heuristic, so server macros stay silent no-ops on the
    client and attribute methods are defined only in `before_first_mount` (once
    `public_columns_hash` is populated). Array-delegated query methods that also
    live in `SERVER_METHODS` (`:first`, `:count`, …) are unaffected — they are
    still routed through `all.send`.
  - **Defensive guard:** `columns_hash` now snapshots
    `public_columns_hash || {}` so the lookup can never dereference `nil`,
    regardless of load order. Verified against the `ru/hyperstack-addons` A/B CI
    that surfaced the regression (Opal 1.5.1 green, 1.8.3 failing).

## 1.0.alpha1.8.34.18.0 — 2026-06-26

### Build & dependencies

- **Bump Ruby 3.3.11 → 3.4.9** (#11). Ruby 3.3 is in security-maintenance only
  (EOL ~March 2027); 3.4 is in full maintenance. Updates `.ruby-version` and the
  CI `RBENV_VERSION` to 3.4.9; the version marker's Ruby segment moves `33 → 34`
  (`1.0.alpha1.8.34.18.0`). The earlier 3.2 → 3.3 jump already cleared the hard
  Opal/Rails-6.1 compatibility work, so this is a straightforward bump.
  - **Prereq:** the CI base image (`base24:yjit`) must ship Ruby 3.4.9 for
    `RBENV_VERSION` to resolve (confirmed: it does).

### Ruby 3.4 compatibility fixes

- **Declare the gems Ruby 3.4 demoted from default to bundled** (`bigdecimal`,
  `mutex_m`, `drb`, `base64`, `logger`) in every component Gemfile. Rails
  6.1.7.x (activesupport) still `require`s them at boot; under `bundle exec`,
  bundler drops default gems not in the Gemfile from the load path, so without
  these every Rails-loading spec job failed with `cannot load such file --
  bigdecimal` / `-- mutex_m`.
- **rails-hyperstack generator:** add the same bundled gems to the generated
  test app's Gemfile, and move the `require "logger"` shim from
  `config/application.rb` to `config/boot.rb`. On Ruby 3.4 `logger` is a bundled
  gem and the `bin/rails` → `rails/commands` path loads activesupport before
  `application.rb`, so the require has to land in `boot.rb` (loaded first) to
  avoid `uninitialized constant ActiveSupport::LoggerThreadSafeLevel::Logger`.
- **hyper-component spec:** `component_spec.rb` no longer interpolates a
  server-side hash to assert rendered output. Ruby 3.4 changed `Hash#inspect`
  to add spaces around `=>` (`{"foo" => "bar"}`), but the client-side Opal
  rendering still emits the pre-3.4 `{"foo"=>"bar"}`; the expectation now
  matches the Opal output literally.

## 1.0.alpha1.8.33.18.0 — 2026-06-26

### Build & dependencies

- **Bump Opal 1.7.4 → 1.8.3** (#14, !24). Updates `OPAL_VERSION` (CI + local-dev
  docs) to 1.8.3 — the larger jump in the Opal line. 1.8 deprecates the `JS` /
  x-string (backtick) API in favour of `Opal::Raw`, and changes several runtime
  semantics (Hash↔Map bridging, `Array#collect` over a mutating buffer,
  `String#object_id`). The dependency ranges already permit it (`opal < 2.0`), so
  no gemspec changes are needed. Version bumped to `1.0.alpha1.8.33.18.0`.

### Opal 1.8 migration

- **Migrate framework `JS::Error` → `Opal::Raw::Error`** with a cross-version
  guard (falls back to `JS::Error` on Opal < 1.8); migrated the test suite off the
  `JS` module to `Opal::Raw`.
- **Opt in to backtick-JavaScript globally** so the codebase's pervasive x-string
  usage compiles cleanly under 1.8. A per-file `# backtick_javascript: true`
  migration is deferred to the eventual Opal 2.0 work. The one-time
  `JS → Opal::Raw` deprecation warning is filtered in the console-cleanliness specs.
- **Define `String#to_key` explicitly** instead of relying on `object_id` (1.8
  changed `String#object_id`).
- **Fix doubled render output**: `RenderingContext` iterates a `dup` of the buffer
  before `collect`, because 1.8's `Array#collect` now visits items appended during
  iteration.
- **Fix param-conversion memoization** under 1.8's Hash→Map bridging: compare the
  passed props by value (`==`) rather than native identity, since native
  hash/array props are re-bridged to a fresh Opal object on every access.

### Fixes

- **hyper-model: guard `infer_type_from_hash` against a nil inheritance column.**
  A non-STI model passed as a typed param (`param :m, type: Model`) has
  `inheritance_column == nil`, so `hash[inheritance_column]` is `hash[nil]`. Under
  Opal 1.8 the Hash→Map bridging makes `native_hash[nil]` return the *whole* hash
  (not nil), which blew up `Object.const_get` with a `Hash`. Now returns the base
  class when there is no inheritance column. Fixes the 1.8-only failures in
  hyper-model `batch4/scope_spec.rb:175` and `batch2/relationships_spec.rb:34`; the
  full hyper-model suite (423 examples) passes on Opal 1.8.3.

## 1.0.alpha1.8.33.17.0 — 2026-06-26

### Build & dependencies

- **Bump Opal 1.6.1 → 1.7.4.** Updates `OPAL_VERSION` (CI + local-dev docs) to
  the latest 1.7.x. The dependency ranges already permit it (`opal-rails ~> 1.0`,
  `opal-sprockets`/`opal-browser` `< 2.0`), so no gemspec changes are needed. The
  disruptive Opal runtime changes (frozen `nil`, strict return-in-block) landed in
  1.6 and were already fixed in `1.0.alpha1.8.33.16.0`; 1.7 adds Ruby 3.2+ syntax
  support, aligning with the Ruby 3.3.11 pin. Version bumped to
  `1.0.alpha1.8.33.17.0`.

## 1.0.alpha1.8.33.16.0 — 2026-06-25 (released)

### Build & dependencies

- **Bump Opal 1.5.1 → 1.6.1 and Ruby 3.2.9 → 3.2.11** (#3).
- **Bump Ruby 3.2.11 → 3.3.11** (#5, !11). Moves the Ruby pin (`.ruby-version` +
  CI `RBENV_VERSION`) to the latest 3.3.x, on top of the Opal 1.6 work it depends
  on. The full browser-spec suite passes on 3.3.11. Version bumped to
  `1.0.alpha1.8.33.16.0`.

### Test suite & CI performance

The hyper-model and hyper-operation browser-spec suites were the slowest part of
CI (model batches ~15–18 min each; hyper-operation part1 ~870s, part2 ~652s). A
sequence of changes brought this down substantially.

- **Split the long spec jobs (#7).** hyper-model split into 7 per-batch jobs
  (`part1`..`part7`) and hyper-operation into 2 (`part1` = the order-sensitive
  `aaa_run_first/*`, `part2` = the rest), to parallelize at the CI-job level.
- **Precompile Opal assets for browser-spec jobs.** The jobs ran
  `config.assets.debug = true` with runtime Sprockets compilation, so every
  browser page boot fetched the Opal bundle as hundreds of per-file requests
  (plus a one-time cold compile). Browser jobs now precompile the static bundle
  once and serve it with `config.assets.compile = false`, gated on the
  `PRECOMPILED_ASSETS` env var (opt-in, so local runs are unchanged). ~5× faster
  per example. Observed: hyper-operation part1 **870s → 161s**, part2 **652s → 134s**.
- **Run specs in parallel by default.** hyper-model now runs all 7 batches in a
  single job across a pool of `PARALLEL_PROCESSES` PostgreSQL databases (each
  worker gets its own DB via `TEST_ENV_NUMBER`); hyper-operation `part2` runs in
  parallel while `part1` stays serial. Parallelism is at the **batch** level for
  hyper-model — each batch runs intact in one process — because the model suite
  has pervasive global ActiveRecord class state (default scopes, default values,
  validations) that file-level distribution would break. Set `PARALLEL_SPECS=0`
  to fall back to the serial path. This replaces the 7 per-batch jobs with a
  single job (~3 CI runners instead of 9); `part1`..`part7` remain as ad-hoc
  per-batch rake tasks.
  - Getting there required isolating per-worker state: a PostgreSQL database per
    process, a per-process Sprockets cache (later mooted by precompilation), and
    batch-level (not file-level) work distribution. A single-thread-Puma attempt
    was tried and reverted — it caused `Net::ReadTimeout` without fixing the
    asset race; precompilation removed the race instead.
- **Reset DatabaseCleaner strategy per example (hyper-model).**
  `DatabaseCleaner.strategy` is global state; the first `js: true` example flipped
  it to `:truncation` and every later non-js example kept truncating needlessly.
  Non-js examples now use a fast `:transaction` rollback again.
- **Per-component gem cache between pipelines.** The `default` cache had no `key`,
  so all ~13 parallel jobs shared one global cache and clobbered each other on
  push (default policy is pull-push), leaving each pipeline to re-resolve gems
  anyway. The cache is now keyed `gems-$COMPONENT` so every component keeps its
  own stable `local_gems` cache (part1/part2 of a component share one key).
  Dropped `node_modules` from the cache: node packages are baked into the image
  at `/node_modules` and symlinked in, so the cached entry was a dangling symlink
  with nothing to restore.
- **Add the Ruby version to the gem cache key** (`gems-$COMPONENT-$RBENV_VERSION`).
  `local_gems` holds installed gems including compiled C extensions, so a cache
  built on one Ruby ABI must not be restored into a job on another (the 3.2 → 3.3
  → 3.4 line). Also a prerequisite for safely sharing the cache across runners
  (shared volume / S3 distributed cache).
- **Reduce CI flakiness in browser specs** — longer Capybara wait + `rspec-retry`.
- **Harden `transports_spec` against cross-example connection leaks** (!16). The
  Transport Tests share the server-side `Hyperstack::Connection` registry but only
  reset Timecop in `after(:each)`, so a connection left open by one example bled
  into the next example's "active connections should be `[]`" assertion and failed
  it deterministically (`rspec-retry` can't help — the leak persists across
  in-process retries). Each example now disconnects all active connections in
  `after(:each)` via the public `Connection.active`/`Connection.disconnect` API.
- **Fix the flaky `transports_spec` "sees the connection going offline" examples**
  (#9) — two compounding causes:
  - *Timing.* The connection's `refresh_at` is stamped when the channel is first
    established — before the test's earlier `Timecop.travel` — so on a slow CI
    runner traveling by exactly `refresh_interval` could land *before* `refresh_at`,
    and `active` never saw `needs_refresh?`. The examples now travel a minute past
    the refresh deadline so the sweep always fires (both transport variants).
  - *Policy (the dominant cause).* An explicitly-denied class connection raised a
    bare `RuntimeError("connection failed")`, but the connection-refresh sweep's
    `channel_allowed_by_policy?` only treats `Hyperstack::AccessViolation` as a
    denial — so the `RuntimeError` fell through to "allow by default" and the
    policy-denied channel was re-stamped and never swept (`got
    ["ScopeIt::TestApplication"]`). `ClassConnectionRegulation.connect` now raises
    `AccessViolation` when a regulation *actively rejects* the user
    (`connectable? == false`), while an absent/empty regulation still raises the
    legacy bare error so unregulated channels stay allowed-by-default (preserving
    the `connection_spec` refresh behaviour). All real callers (subscribe /
    `can_connect?`) rescue both alike; the one explicit-denial assertion in the
    `regulate_class_connection` contract specs was updated to expect `AccessViolation`.

### Security

- **Enforce the connection policy on `connect-to-transport`** (#12). The
  `connect_to_transport` controller action re-registered a channel via
  `Connection.open` **without** a policy check — unlike `subscribe` — so a client
  the connection policy denied could resurrect a channel the refresh sweep had
  just dropped (and was the residual race behind the #9 offline-test flake). The
  action now calls `regulate(params[:channel])` first (skipping the per-client
  session channel) and returns `401 Unauthorized` on an `AccessViolation`.

### Fixes

- **hyper-spec: stub unserializable collections** in `opal_serialize` instead of
  emitting invalid Opal, with specs for collection stubbing (#2).
- **hyper-i18n: guard Store reads against an uninitialized Store** (#1, !15).
  `t`/`t_async`/`preload`/`l` read `Store.translations`/`Store.localizations`
  before the client-only i18n Store is guaranteed initialized, raising
  `undefined method 'translations' for nil` during early component mount (e.g. a
  `before_mount`-triggered preload, or a non-default-locale transient). Benign
  today (swallowed by callers) but real ordering noise. New
  `translations_store`/`localizations_store` helpers degrade to `{}` instead of
  raising; writes in resolved-promise callbacks (after init) are unchanged.
