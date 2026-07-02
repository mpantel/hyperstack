# Changelog

Project-wide changelog. Version-scoped release notes for the v23–v28 Redis
connection work live in [`CHANGELOG_v23-v28.md`](./CHANGELOG_v23-v28.md);
hyper-component has its own [`CHANGELOG`](./ruby/hyper-component/CHANGELOG.md).

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
