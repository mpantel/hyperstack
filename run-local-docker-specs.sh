#!/usr/bin/env bash
#
# Run a gem's browser specs locally against Dockerized Postgres + Chrome.
#
# This mirrors how the CI browser-spec jobs run, but on a developer machine with
# nothing installed beyond Docker + the Ruby toolchain. It spins up two throwaway
# containers (both on the host network), prepares the DB and the precompiled Opal
# bundle, then runs RSpec against the remote Chrome.
#
# Usage:
#   ./run-local-docker-specs.sh [COMPONENT] [SPEC_PATH]
#
#   COMPONENT   gem dir under ruby/ (default: hyper-model)
#   SPEC_PATH   rspec path relative to the gem (default: spec)
#               e.g. spec/batch4  or  spec/batch4/scope_spec.rb:175
#
# Env overrides:
#   OPAL_VERSION (default 1.8.3), TZ (default Etc/UTC; MUST match between the
#   server and the browser or datetime specs fail — see note below).
#
# Cleanup:
#   docker rm -f hs-postgres hs-chrome
#
set -euo pipefail

COMPONENT="${1:-hyper-model}"
SPEC_PATH="${2:-spec}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export OPAL_VERSION="${OPAL_VERSION:-1.8.3}"
export TZ="${TZ:-Etc/UTC}"
# Opal 1.8's prefork build scheduler forks workers and hangs in some sandboxes.
export OPAL_PREFORK_DISABLE=1
# Build the static Opal bundle once; specs then run with compile=false. Without
# this the on-the-fly debug pipeline recompiles per request and the first spec
# appears to hang for minutes.
export PRECOMPILED_ASSETS=1
export DISABLE_SPRING=1
export RAILS_ENV=test
export PGHOST=localhost PGPORT=5432 PGUSER=postgres
export DRIVER=remote SELENIUM_REMOTE_URL=http://localhost:4444/wd/hub
export PARALLEL_SPECS=0

echo "==> Ensuring Docker containers (host network)"
# Postgres: trust auth, role 'postgres'.
if ! docker ps --format '{{.Names}}' | grep -qx hs-postgres; then
  docker rm -f hs-postgres >/dev/null 2>&1 || true
  docker run -d --name hs-postgres --network host \
    -e POSTGRES_HOST_AUTH_METHOD=trust -e POSTGRES_USER=postgres postgres:16 >/dev/null
fi
# Selenium standalone Chrome: hub on localhost:4444, browser reaches the host
# Puma server directly because of --network host.
if ! docker ps --format '{{.Names}}' | grep -qx hs-chrome; then
  docker rm -f hs-chrome >/dev/null 2>&1 || true
  docker run -d --name hs-chrome --network host \
    -e TZ="$TZ" selenium/standalone-chrome:latest >/dev/null
fi

echo "==> Waiting for Postgres"
until docker exec hs-postgres pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done

cd "$ROOT/ruby/$COMPONENT"

echo "==> bundle install ($COMPONENT, opal $OPAL_VERSION)"
bundle install --quiet
( cd spec/test_app && bundle install --quiet )

echo "==> Preparing test DB"
( cd spec/test_app && bundle exec rails db:create db:migrate >/dev/null )

# jsbundling-rails (#19 esbuild): build the JS bundles in a node container (the
# host has no Node), then skip jsbundling's own assets:precompile build hook so
# the Opal precompile below runs without needing Node on the host. In CI (Node in
# base24) SKIP_JS_BUILD is unset, so the hook builds automatically.
if [ -f spec/test_app/package.json ] && grep -q '"build"' spec/test_app/package.json; then
  echo "==> Building JS bundles (esbuild via node:24, yarn)"
  docker run --rm --network host -v "$ROOT/ruby/$COMPONENT/spec/test_app":/app -w /app \
    node:24 sh -c "corepack enable 2>/dev/null; yarn install --silent && yarn build" >/dev/null
  export SKIP_JS_BUILD=1
fi

echo "==> Precompiling Opal assets"
( cd spec/test_app \
  && rm -f public/assets/.sprockets-manifest-*.json public/assets/manifest-*.js public/assets/application-*.js \
  && bundle exec rails assets:precompile >/dev/null )

echo "==> Running: rspec $SPEC_PATH  (TZ=$TZ)"
bundle exec rspec "$SPEC_PATH" --format progress
