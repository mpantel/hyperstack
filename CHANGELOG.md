# Changelog

Project-wide changelog. Version-scoped release notes for the v23–v28 Redis
connection work live in [`CHANGELOG_v23-v28.md`](./CHANGELOG_v23-v28.md);
hyper-component has its own [`CHANGELOG`](./ruby/hyper-component/CHANGELOG.md).

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
