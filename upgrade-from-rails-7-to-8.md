# Upgrading a Hyperstack app from Rails 7 to Rails 8

> **Status** — Hyperstack's own Rails 8 migration (issue #20) and the Ruby 4.0
> bump (#15) are complete. Since `1.0.alpha1.9` there is no separate Rails 8
> branch: one gem set covers Rails 6.1 through 8.1, and Rails 8.0 and 8.1 are
> each tested on both Ruby 3.4 and Ruby 4.0 — four cells of the matrix in
> [`supported_versions.yml`](./supported_versions.yml). Steps below were
> compiled as each incompatibility was found during that migration. It builds on
> the [Rails 6→7 guide](./upgrade-from-rails-6-to-7.md) and the
> [official Rails upgrade guide](https://guides.rubyonrails.org/upgrading_ruby_on_rails.html).

This is for **apps built on Hyperstack** moving from Rails 7.x to Rails 8
(targeting 8.1).

## The Opal asset pipeline is the main change

Rails 8 forces a decision about how the Opal bundle is compiled, because the gem
that used to wire Opal into the Rails asset pipeline no longer fits:

- **`opal-rails` 2.x is hard-capped at `rails < 7.3`** — it will not resolve on
  Rails 8 at all (`Could not find compatible versions … opal-rails … requires
  rails >= 6.0, < 7.3`).
- **`opal-rails` 3.0** *does* support Rails 8, but it is a **ground-up rewrite**:
  it drops the classic sprockets `//= require` Opal processor and instead
  compiles entrypoints from `app/opal/*.rb` into static `app/assets/builds/*.js`
  via an `opal:build` rake task (auto-hooked into `assets:precompile`,
  `test:prepare`, `spec:prepare`). With the classic `//= require
  hyperstack-loader` setup it aborts precompile with
  `Opal::Rails::MissingEntrypointError: Opal entrypoints_path app/opal does not
  exist`.

Hyperstack itself took the **lower-risk path** (issue #20): keep the classic
`//= require hyperstack-loader` sprockets pipeline and depend directly on
**`opal-sprockets`** (the gem that actually provides the sprockets Opal
processor — `opal-rails` 2.x only wrapped it). `opal-sprockets 1.0.4` has **no
rails cap** and resolves cleanly with Rails 8.1.

### Gemfile / gemspec

- **Drop `opal-rails`, add `opal-sprockets`:**
  ```ruby
  # gem 'opal-rails', '~> 2.0'   # remove — capped at rails < 7.3
  gem 'opal-sprockets', '~> 1.0'
  gem 'sprockets-rails'          # still required (declared since Rails 7)
  gem 'sprockets', '~> 4.0'
  ```
- **Bump Rails:** `gem 'rails', '~> 8.1'` (or `'~> 8.0'` — both are tested cells).
- **`react-rails`:** pin `~> 2.7`. With a loose `>= 2.4, < 3.0` range, bundler on
  Rails 8 can nondeterministically resolve the older 2.6.2 (React 16 line),
  which breaks the connection_pool shim / React 17 line (#29).

### Replacing opal-rails' Rails wiring

`opal-sprockets` registers the sprockets transformer for `.rb`/`.js.rb` on
load, but (unlike `opal-rails`) ships **no railtie** — so an app must reproduce
the two things `opal-rails`' engine did. Hyperstack does this in its own railtie
(`hyperstack-config`), so **apps that boot through `hyperstack-config` need no
change**. If you wired Opal yourself, add an initializer:

```ruby
# after sprockets-rails' :append_assets_path
initializer 'opal.append_assets_path', after: :append_assets_path do |app|
  app.config.assets.paths.unshift(*Opal.paths) if app.config.respond_to?(:assets)
end
# and, if you use config.opal.* settings, push them through to Opal::Config
# in an after_initialize hook.
```

Also keep `.rb` Opal sources out of eager/autoload paths so Zeitwerk doesn't try
to load them as constants:

```ruby
config.before_initialize do |app|
  app.config.eager_load_paths =
    app.config.eager_load_paths.dup - Dir["#{app.root}/app/{assets,views}"]
end
```

There is **no `app/opal` directory** and no `opal:build` step in this model —
everything still flows through `//= require hyperstack-loader` and
`assets:precompile`. (Adopting `opal-rails 3.0`'s entrypoint layout — which
would unify the Opal bundle with the esbuild `app/assets/builds` output from
#19 — is tracked separately in **#37**.)

## Routing

- **Dynamic route registration must use `routes.append`.** The
  `routes.disable_clear_and_finalize` / `clear!` / `draw` / `routes_reloader` /
  `finalize!` dance no longer registers routes on Rails 8 (they silently vanish —
  `No route matches [GET] …`). Use the supported append API, which is re-applied
  on every reload and coexists with the app's own routes:
  ```ruby
  Rails.application.routes.append do
    get '/my/path/:id', to: 'my#action'
  end
  Rails.application.reload_routes!
  ```
  Hyperstack's own test harness (`hyper-spec`) was fixed this way; check any
  app/engine code that manipulates `Rails.application.routes` directly.

## Config

- **`config.load_defaults`** — Rails 8 still loads older framework defaults
  (`5.1`, `7.2`, …); bumping to `8.0`/`8.1` is optional and opt-in per the
  official guide. Hyperstack's test_apps run unchanged.
- **Propshaft is the new default asset pipeline**, but Hyperstack serves the Opal
  bundle through **sprockets**, so keep `sprockets` + `sprockets-rails` and do
  **not** switch to propshaft. (`react-rails` supports both.)
- `config/secrets.yml` / `Rails.application.secrets` were already removed in 7.2 —
  see the 6→7 guide if you still reference them.

## ActiveRecord

- **`enum` requires the positional signature.** The keyword-hash form
  `enum test_enum: [:yes, :no]` (valid through Rails 7.0) raises
  `ArgumentError: wrong number of arguments (given 0, expected 1..2)` on Rails 8.
  Use the positional form:
  ```ruby
  enum :test_enum, [:yes, :no]     # was: enum test_enum: [:yes, :no]
  ```
  Hyperstack's isomorphic models are safe either way — the client-side
  (ReactiveRecord) `enum` is a no-op that ignores its args — so this is a pure
  server-side (ActiveRecord) requirement.

## Ruby 4.0

Rails 8 runs on Ruby 4.0. Hyperstack's stack moved to **Ruby 4.0.5** (#15)
alongside this upgrade:

- Ruby 4.0 is a **major** version — audit for removed/long-deprecated APIs and
  stdlib gems that 3.x only warned about.
- Native extensions recompile against the new ABI (`mini_racer` / `libv8-node`
  build clean on 4.0.5).
- **Opal 1.8.3 runs fine on a Ruby 4.0 host** — the compiler runs on the host
  Ruby and the compiled output is unchanged.

## Related

- **#37** — adopt `opal-rails 3.0` (`app/opal` entrypoints), unifying the Opal
  bundle with the esbuild `app/assets/builds` output (#19) and easing an eventual
  move to propshaft.
- **#29** — retire `react-rails`; would also drop the `~> 2.7` pin above.
