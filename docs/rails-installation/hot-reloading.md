# Hot Reloading

Hyperstack ships a hot-reloader that re-evaluates your Ruby (and CSS) in the
running browser the moment you save a file, then re-renders your components —
no page refresh, no lost client-side state. It is intended for development only.

There are two halves and **both** must be in place:

1. A **server** process that watches your source directories and pushes changes
   over a websocket.
2. A small **client** that runs in the browser, receives those changes,
   `eval`s the new code, and forces a re-render.

The Hyperstack installer (`bundle exec rails hyperstack:install`) wires up both
for you unless you pass `--skip-hotloader`. The sections below describe what it
sets up so you can add, verify, or customize it yourself.

## The server process

The installer adds a `Procfile` and the `foreman` gem (in the `:development`
group):

```
web:        bundle exec rails s -b 0.0.0.0
hot-loader: bundle exec hyperstack-hotloader -p 25222 -d app/hyperstack
```

Start everything with:

```
bundle exec foreman start
```

`hyperstack-hotloader` watches the directories passed with `-d` (plus
`app/assets/javascripts`, `app/assets/stylesheets` and `app/views/components`
if they exist) for changes to `*.rb`, `*.rb.erb` and `*.s?[ac]ss` files. When a
file changes it pushes the new source down the websocket on the port given with
`-p` (default `25222`).

## The client

The installer adds this import to `config/initializers/hyperstack.rb`, guarded so
it is only bundled for development:

```ruby
Hyperstack.import 'hyperstack/hotloader', client_only: true if Rails.env.development?
```

Importing `hyperstack/hotloader` is all that is required — the client connects
to the websocket automatically as soon as the bundle loads in a real browser. (It
does nothing during server-side prerendering or on the Rails server, where there
is no websocket to open.) If you want hot reloading in another non-production
environment, add the import there too; production never imports it.

> The connection is opened automatically on boot. Earlier versions required you
> to call `Hyperstack::Hotloader.listen` by hand from a boot file; that is no
> longer necessary and you should remove any such call.

## Settings

These can be set in `config/initializers/hyperstack.rb`. The client reads them
from the JS config emitted alongside the bundle, so **the port must match** the
`-p` value used to start `hyperstack-hotloader`.

```ruby
# Port the client connects to; must match the Procfile's `hyperstack-hotloader -p`.
Hyperstack.hotloader_port = 25222
# Seconds between keep-alive pings over the websocket. Normally not needed.
Hyperstack.hotloader_ping = nil
# Hot reloading automatically reloads callbacks when affected classes are
# reloaded. Not recommended to change this.
Hyperstack.hotloader_ignore_callback_mapping = false
```

## Verifying it works

With `foreman start` running and a page open in the browser:

1. The browser console prints `Hot-Reloader connecting to <host>:25222` on load.
2. Edit a component under `app/hyperstack` and save.
3. The hot-loader process logs the changed file, and the component re-renders in
   place without a full page reload.

If nothing happens, check that the port in `Hyperstack.hotloader_port` matches the
`-p` value in your `Procfile`, and that the `hot-loader` process is actually
running.
