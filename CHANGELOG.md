# Changelog

Project-wide changelog. Version-scoped release notes for the v23–v28 Redis
connection work live in [`CHANGELOG_v23-v28.md`](./CHANGELOG_v23-v28.md);
hyper-component has its own [`CHANGELOG`](./ruby/hyper-component/CHANGELOG.md).

## 2026-06-25

### Build & dependencies

- **Bump Opal 1.5.1 → 1.6.1 and Ruby 3.2.9 → 3.2.11** (#3).

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
- **Reduce CI flakiness in browser specs** — longer Capybara wait + `rspec-retry`.

### Fixes

- **hyper-spec: stub unserializable collections** in `opal_serialize` instead of
  emitting invalid Opal, with specs for collection stubbing (#2).
