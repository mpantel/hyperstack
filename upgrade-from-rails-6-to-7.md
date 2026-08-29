# Upgrading a Hyperstack app from Rails 6.1 to Rails 7

> **Status** — Hyperstack's own Rails 7.2 migration (issue #16) is complete.
> Since `1.0.alpha1.9` there is no separate Rails 7 branch: one gem set covers
> Rails 6.1 through 8.1, and Rails 7.2 is tested with both React 16.14 and
> React 19.2 — two cells of the matrix in
> [`supported_versions.yml`](./supported_versions.yml). Steps below were compiled
> as each incompatibility was found during that migration.

This guide is for **apps built on Hyperstack** moving from Rails 6.1 to Rails 7.x
(targeting 7.2). It covers the Hyperstack-specific friction on top of the
[official Rails upgrade guide](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html).

## Gemfile

- **Bump Rails:** `gem 'rails', '~> 7.2'`.
- **Add `sprockets-rails` explicitly.** Rails 7 decouples `sprockets-rails` from
  `rails`. Without it, `config.assets` does not exist and boot fails with
  `undefined method 'assets' for Rails::Application::Configuration`. Hyperstack
  serves the Opal bundle through sprockets, so this gem is required:
  ```ruby
  gem 'sprockets-rails'
  ```
- **Keep `sprockets` below 4.2.** sprockets `>= 4.2` raises `can't modify
  immutable cached environment` and breaks Opal asset compilation. Pin it:
  ```ruby
  gem 'sprockets', '~> 4.0', '< 4.2'
  ```
- **Pin `opal-rails '~> 2.0'`.** opal-rails **3.0** is a Rails-7 rewrite that
  requires a new `app/opal` entrypoints directory; with the classic sprockets
  setup (`//= require hyperstack-loader`) it aborts asset precompile with
  `Opal::Rails::MissingEntrypointError: Opal entrypoints_path app/opal does not
  exist`, and the browser then reports `Opal is not defined`. opal-rails **2.0.4**
  supports `rails < 7.3` (so 7.2 works) and keeps the classic convention:
  ```ruby
  gem 'opal-rails', '~> 2.0'
  ```
  (Adopting opal-rails 3.0's entrypoint layout is a larger, separate change.)
- **Bump `react-rails` to `>= 2.7`.** Earlier versions (`< 2.7`) don't support
  Rails 7. react-rails **2.7.1** keeps the existing `ReactDOM.render` mount path,
  but ships a newer bundled **React (17.0.2)** than the 2.6.x line (React 16.14).
  If your specs assert on React console output, note two React console format
  changes:
  prop-type warnings now log the *unsubstituted* format string
  (`console.error("Warning: Failed %s type: %s%s", "prop", …)`), and the
  `componentDidCatch` `componentStack` no longer carries component names for
  components created via `create-react-class`. (Moving to React 18's `createRoot`
  is a separate change.)
- **Asset pipeline (if your app uses Webpacker):** Rails 7 drops Webpacker.
  Migrate to **Shakapacker** (its maintained successor) — closest drop-in:
  rename the gem (`gem 'shakapacker'`), `bin/rails shakapacker:install`, and
  rename `config/webpacker.yml` → `config/shakapacker.yml`. (Apps that serve
  everything through sprockets don't need this.)

## Config

- **`Rails.application.secrets` was removed in Rails 7.2.** Replace any use with
  `Rails.application.secret_key_base` (or Rails credentials). Hyperstack's own
  transport code was updated; check your app for direct `secrets` access.
- **`config/secrets.yml` is no longer read** in 7.2 — move `secret_key_base` to
  credentials or `ENV` / `config.secret_key_base`.

## Test suite (hyper-spec / rspec-rails)

- **Require `rspec-rails >= 7.0`** (and `rspec >= 3.13`). Older rspec-rails
  (6.0.x) calls the group-level `fixture_path=` that Rails 7.2 removed from
  `ActiveRecord::TestFixtures`, so specs fail to load with
  `undefined method 'fixture_path=' for class RSpec::ExampleGroups::...`. Watch
  for a stale `gem 'rspec', '~> 3.11'` pin holding rspec-core below 3.13 — that
  silently caps rspec-rails at 6.0.
- **`config.fixture_path=` → `config.fixture_paths=`** (array). rspec-rails 7
  removed the singular string setter:
  ```ruby
  # before
  config.fixture_path = Rails.root.join('spec/fixtures').to_s
  # after
  config.fixture_paths = [Rails.root.join('spec/fixtures').to_s]
  ```

## ActiveRecord

- **`serialize` requires an explicit `coder:` (Rails 7.1+).** The positional/no-
  coder forms (`serialize :col` / `serialize :col, JSON`) raise
  `missing keyword: :coder`. The historical default was YAML, so the
  drop-in-compatible change is:
  ```ruby
  serialize :col, coder: YAML   # was: serialize :col
  ```
- **`ActiveRecord::InternalMetadata` / `SchemaMicration` are no longer
  `ActiveRecord::Base` subclasses (7.1+)** — code that reopened or iterated AR
  models and touched them may need a guard.

## Autoloading (Zeitwerk)

Rails 7 is **Zeitwerk-only** (the classic autoloader is gone, even with
`config.load_defaults 5.1`). The key behavioural change to watch for:

- **`defined?(Foo)` / `const_defined?('Foo')` is truthy for any *autoloadable*
  constant**, because Zeitwerk registers a `Module#autoload` for every class
  under `app/*`. Code that used these to mean "already loaded" now silently
  treats not-yet-loaded classes as loaded. Check for a *pending autoload*
  instead:
  ```ruby
  loaded = Object.const_defined?('Foo') && !Object.autoload?('Foo')
  ```
  Hyperstack's `ServerDataCache.get_model` and `PolicyAutoLoader` were updated
  for this (the former mattered for security: the old check let a client string
  force-load arbitrary `app/*` classes under Zeitwerk).
- A policy/model file that exists but doesn't define its expected constant
  raises `Zeitwerk::NameError` ("expected file … to define constant …"), where
  the classic autoloader raised `LoadError`.
- **`config.autoloader` and `ActiveSupport::Dependencies.require_or_load` are
  gone.** Code that branched on `Rails.configuration.autoloader == :zeitwerk`
  silently takes the wrong path on Rails 7 (the config returns nil). Detect
  Zeitwerk with `Rails.autoloaders.zeitwerk_enabled?` instead, and guard any
  monkey-patch of `require_or_load` with `respond_to?(:require_or_load, true)`.

## Generator / new apps

- Rails 7 `rails new` no longer bundles **Spring** (`spring stop` exits 127) or
  **Webpacker** (`rails webpacker:install` is unrecognized).
- For a sprockets-served Opal app, generate with **`--skip-javascript`** so Rails
  doesn't scaffold importmap/jsbundling — otherwise its `app/javascript/
  application.js` collides with the sprockets `application.js`
  (`Sprockets::DoubleLinkError`).

## Related

- Ruby: Rails 7 runs fine on Ruby 3.4; note Ruby 3.4 also requires declaring the
  gems demoted from default to bundled (`bigdecimal`, `mutex_m`, `drb`, `base64`,
  `logger`) — see the Ruby 3.4 upgrade notes.
- **Rails-6-era pins you can now drop on 7.2:** the `concurrent-ruby '1.3.4'`
  pin (an `ActiveSupport::Logger` workaround "not needed after rails 7.1") and
  the `net-imap '0.4.18'` pin are obsolete — let both float. The `sqlite3 '< 2'`
  cap (rails/rails#35153) can be lifted; Rails 7.2 supports `sqlite3 ~> 2.0`.
- A later move off the Webpacker lineage to a Rails-native bundler, and the jump
  to Rails 8.x, are tracked separately.
