# The supported-configuration matrix

Hyperstack is tested against several combinations of Ruby, Rails, Opal, React and
asset pipeline at once. Each combination is called a **cell**, and every cell is
declared in one file: [`supported_versions.yml`](../../supported_versions.yml) at
the repository root.

This page explains what a cell is, and how to add or remove one.

## Why there is exactly one table

The obvious way to run a version matrix is to list the combinations in the CI
config. The problem is that a project then has *two* answers to "what do we
support" — the CI file, and whatever the README or gemspec claims — and they
drift apart silently. The version you tell users about stops being the version
you actually run.

So `supported_versions.yml` is the single source of truth, with two consumers
that both read it:

1. **CI** — one pipeline cell per entry. `rake hyperstack:matrix:check` fails the
   pipeline if `.gitlab-ci.yml` and the table disagree, so a combination we claim
   to support is one that actually gets tested.
2. **Runtime** — `Hyperstack::SupportedVersions` checks a booting app against the
   table and reports where it sits. `rake hyperstack:config:check` does the same
   from the command line.

The rule that falls out of this: **never edit the cell list in `.gitlab-ci.yml`
alone.** The check exists to catch exactly that.

## Anatomy of a cell

```yaml
  - id: rails72-react19
    ruby:        "3.4"
    rails:       "7.2"
    opal:        "1.8"
    react_rails: "3.3"       # for react_ujs; React itself comes from npm
    pipeline:    sprockets
    react:       "19.2"      # derived: npm via esbuild
    env:
      RAILS_VERSION: "~> 7.2"
      OPAL_RAILS_VERSION: "~> 2.0"
      REACT_RAILS_VERSION: "~> 3.3"
      HYPERSTACK_REACT_SOURCE: "npm"
      REACT_NPM_VERSION: "~19.2.0"
      HYPERSTACK_JS_PIPELINE: esbuild
```

| field | meaning |
|---|---|
| `id` | Names the cell. Used by CI as the image tag and cache key. |
| `ruby`, `rails`, `opal`, `react_rails` | `major.minor`. What this cell asserts it runs. |
| `pipeline` | How Opal/assets are delivered (`sprockets` today for every cell). |
| `react` | **Derived, not selected** — see below. |
| `env` | What CI exports for this cell, resolved by `rake hyperstack:cell:env`. |

### `react` is derived

Nothing installs React directly. It is whatever `react_rails` plus the JS
pipeline actually deliver: react-rails 2.x bundles React 16.x, react-rails 3.3
bundles 18.2, and the esbuild pipeline takes React from npm instead. The field
records the real span so the table documents reality, but you do not *choose* it
— you choose the things that produce it, then write down what came out.

This is not a formality. The value used to be derived by reading `package.json`,
and one cell was found to be advertising a React it was not running.
`ruby/hyper-spec/spec/cell_contract_spec.rb` now asserts, in the browser, that
`window.React.version` matches this field for whichever cell CI is running. A
cell that drifts from its declaration fails there.

### `env` and the version selectors

`env` is applied *after* the pipeline's own variables, so a cell overrides the
global default. Leaving a variable out takes the **gemspec default** — which is
why the cell describing today's default configuration can have an empty `env` and
be a no-op.

The gemspecs read these through `Hyperstack.version_selector`, which treats blank
as unset. So `RAILS_VERSION: ""`, a bare key with no value (YAML reads it as
nil), and omitting the key entirely all mean the same thing: take the gemspec
default. None of them can reach Bundler as the requirement `''`.

A consequence worth knowing: **widening a gemspec default silently moves every
cell that was relying on it.** When the `rails` cap widened to `< 9.0`, the older
cells had to start pinning `RAILS_VERSION` explicitly, or they would have floated
off their own axis.

### The `id` naming rule

`id` is `rails<MM>-react<MM>`, and it names *only* the axes that distinguish a
cell from its siblings. A `-ruby<MM>` suffix is added **only** where two cells
would otherwise collide — today the Rails 8.0 and 8.1 pairs, each run on both
Ruby 3.4 and Ruby 4.0.

So an unsuffixed id never implies a particular Ruby. Every other cell's Ruby
lives in its `ruby:` field and nowhere else.

Ids are consumed by CI alone (image tag, cache key); the runtime check matches on
the `ruby`/`rails` fields. Renaming one therefore costs an image rebuild and
nothing else.

## How the runtime check classifies an app

`Hyperstack::SupportedVersions.status` returns one of three values:

| status | meaning |
|---|---|
| `:supported` | Matches a cell exactly — this combination has a CI pipeline. |
| `:untested` | Inside the spans we cover on every axis, but not a cell anyone runs. |
| `:unsupported` | Outside the spans entirely. |

The spans are **derived** from the cells: for each axis, `min..max` of the values
present in the table. This is why adding or removing a cell at the edge of an
axis changes what apps are classified as unsupported, even if you were only
thinking about CI.

`:untested` matters, and is why the middle value exists: a hard failure there
would refuse combinations that very likely work and that nobody asked us about.
`check!` warns on `:untested` and raises on `:unsupported` by default.

## Adding a version

Worked example: the commit that added `rails72-react19` (#95).

### 1. Decide what the cell proves

Prefer a cell that moves **one axis** from an existing one. Then a failure is
attributable: if `rails72-react16` and `rails72-react19` differ only in React, a
failure in the second is a React failure.

Cells that move several axes at once are sometimes justified — but say so in the
comment, because the diagnostic value is lower and the next person should know it
was deliberate.

### 2. Add the entry to `supported_versions.yml`

Compose `env` from the cells that already establish each axis, rather than
inventing values. `rails72-react19` is literally the union of two working cells:
Rails and `OPAL_RAILS_VERSION` from `rails72-react16`, the React 19 half
(`HYPERSTACK_REACT_SOURCE: npm`, `REACT_NPM_VERSION`, `react-rails 3.3` for
`react_ujs`) from `rails61-react19`.

Write a comment saying **why the cell exists and what it moves**. The table is
the project's explanation of its own support policy; a bare row does not explain
itself later.

Pin npm React to a series (`~19.2.0`), not a caret range (`^19.0.0`) — the
contract spec compares the browser's actual version against `react:`, and a caret
range will float onto the next minor and fail.

### 3. Add the id to `.gitlab-ci.yml`

Three lists must include it — they are all `parallel: matrix:` axes:

- `.test_gem_pg`
- `.test_gem`
- `build-cell-image`

### 4. Verify before pushing

```bash
rake hyperstack:matrix:check                          # table <-> CI agree
HYPERSTACK_CELL=rails72-react19 rake hyperstack:cell:env   # env resolves
cd ruby/hyperstack-config && bundle exec rspec \
  spec/supported_versions_spec.rb spec/version_selectors_spec.rb
```

`matrix:check` prints the cell count and the full list on success, and names
exactly which ids are missing or extra on failure. It also runs as its own
pipeline job, and `rake publish` depends on it.

### 5. Build the cell image

Each cell has a Docker image, `$CI_REGISTRY_IMAGE/cell:<id>`, built from
`docker/cell-image/` with gems and the yarn cache prebaked. A new cell has no
image until `build-cell-image` runs for it — that job is `when: manual`, so
trigger it from the pipeline for the new cell before expecting the test jobs to
pass.

### 6. Let the contract spec confirm it

`cell_contract_spec.rb` runs in every cell and asserts the *running* Ruby, Rails,
Opal, react-rails and browser React against the declaration. It prints
`[CELL] <id>: window.React.version=... declared=...`, so the job log shows what
actually loaded. This is the step that catches a cell whose `env` does not
produce what the row claims.

## Removing a version

1. Delete the entry from `supported_versions.yml`.
2. Remove the id from all three lists in `.gitlab-ci.yml`.
3. `rake hyperstack:matrix:check` — it fails on `run by CI but not declared` if
   you missed a list.
4. Check whether the removal moved an **axis span**. Dropping the lowest Rails
   cell raises the floor, and apps below it go from `:untested` to
   `:unsupported` — a user-visible change in behaviour, not just less CI.
5. Consider whether an `id` still needs its disambiguating suffix. If removing a
   cell leaves its sibling alone on an axis, the `-ruby<MM>` suffix is now
   noise — though renaming costs an image rebuild.
6. The registry image for the removed cell becomes garbage; delete the tag if you
   are tidying.

## What a cell costs

A cell is not free, and adding one is a real decision:

- one more image to build and store, and
- one more full pass of the suite in every pipeline.

That cost is what #57 and #58 are about — #58's answer being a reduced default
matrix with the full one on protected branches and on demand, which is also why
the raw cell count is the wrong thing to economise on. Weigh the cost against
what the cell tells you that no other cell can.

If the answer is "not worth a cell", record *that* — the header of
`supported_versions.yml` is the place to say a combination is deliberately
uncovered, so the next person does not re-litigate it from scratch.

## Gotchas

- **Editing only `.gitlab-ci.yml`.** The check exists for this; it will fail.
- **A caret npm range.** Floats onto the next React minor and fails the contract
  spec.
- **Assuming an unsuffixed id means a particular Ruby.** It does not; read
  `ruby:`.
- **Widening a gemspec default.** Every cell that was relying on that default
  moves with it. Pin the cells that must not move.
- **Forgetting the image.** A new cell's test jobs cannot pass until
  `build-cell-image` has run for it.
- **A removal that changes a span.** Check the runtime classification, not just CI.

## See also

- [`supported_versions.yml`](../../supported_versions.yml) — the table, with a
  comment per cell explaining why it exists
- `Rakefile` — `hyperstack:matrix:check`, `hyperstack:cell:env`,
  `hyperstack:config:check`
- `ruby/hyperstack-config/lib/hyperstack/supported_versions.rb` — the runtime check
- `ruby/hyper-spec/spec/cell_contract_spec.rb` — the declaration-vs-reality assertion
- `docker/cell-image/` — how a cell image is built
