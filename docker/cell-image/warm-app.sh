#!/usr/bin/env bash
# Warm the image for the app `rake spec:prepare` generates at job time (#75).
#
# #73 prebaked the gems spec:prepare installs by hand. This does the same for the
# ones it installs *implicitly*: `rails new` bundles a ~76-gem application
# (sassc, sqlite3, byebug, bootsnap, web-console, ...) and, on the Webpacker
# cells, `webpacker:install` downloads a large npm tree. None of that is in
# `local_gems` either -- the app's bundle has no `--path`, so it lands in
# GEM_HOME, and npm packages went to a yarn cache the test jobs never actually
# had (their `cache: []` overrides `default:`, it does not merge with it).
#
# So: generate a throwaway app here, exactly as spec:prepare will, let it install
# everything, then delete the app and keep what it left behind. Measured on
# rails61-react17:
#
#   step                    cold    warm
#   rails new + bundle       70s      5s
#   bundle (app Gemfile)     11s      3s
#   webpacker:install        51s     29s
#   ------------------------------------
#                           132s     37s     ~95s off every job
#
# Nothing here hardcodes a version or a package: the rails version, the JS
# pipeline and the Gemfile additions all come from spec_prepare_gems.rb, the same
# definitions spec:prepare itself reads.
set -euo pipefail

SPG=/hyperstack/ruby/rails-hyperstack/spec_prepare_gems.rb
APP=/tmp/warm_app

: "${YARN_CACHE_FOLDER:?set YARN_CACHE_FOLDER to the directory to warm}"
mkdir -p "$YARN_CACHE_FOLDER"

# Spring would fork a server that outlives the build layer; CI disables it for
# the same reason (DISABLE_SPRING=1 in .gitlab-ci.yml).
export DISABLE_SPRING=1

# Ruby 3.4 + Rails 6.1: activesupport touches ::Logger before requiring it, so
# even `rails new` can die with "uninitialized constant
# LoggerThreadSafeLevel::Logger" once the app's own gems are on the path.
# spec:prepare fixes the generated app through config/boot.rb (below); the
# commands this script runs need the same guarantee from the outside.
export RUBYOPT="-rlogger ${RUBYOPT:-}"

RAILS_V="$(ruby "$SPG" --rails-version)"
PIPELINE="$(ruby "$SPG" --js-pipeline)"
echo "warming for rails ${RAILS_V} (${PIPELINE} pipeline), yarn cache ${YARN_CACHE_FOLDER}"

rm -rf "$APP"

# --skip-javascript on the esbuild cells, for the reason spec:prepare gives: the
# scaffolded importmap/jsbundling entry point collides with the one the esbuild
# strategy writes (Sprockets::DoubleLinkError). (#51)
SKIP_JS=""
[ "$PIPELINE" = "webpacker" ] || SKIP_JS=" --skip-javascript"
# shellcheck disable=SC2086
rails "_${RAILS_V}_" new "$APP" -T${SKIP_JS}

cd "$APP"
ruby "$SPG" --app-bundled-gems | while read -r gem_name; do
  echo "gem \"${gem_name}\"" >> Gemfile
done
# config/boot.rb loads before bundler/setup, which is the only place early enough
# to define Logger for Rails 6.1 on Ruby 3.4. Mirrors spec:prepare.
ruby -e 'f="config/boot.rb"; File.write(f, %Q(require "logger"\n)+File.read(f))'
bundle install

# The npm side. Only the Webpacker cells have a `webpacker:install` to run, and
# it is where the download cost is: 13 yarn invocations, of which the fetch phase
# is what a warm cache removes. The esbuild cells install their packages from a
# package.json the hyperstack generator writes, which needs the gem's source --
# not present in this image -- so they get the gem warm-up only, and their yarn
# cost is small (~7s) anyway.
if [ "$PIPELINE" = "webpacker" ]; then
  bundle exec rails webpacker:install
fi

cd /
rm -rf "$APP"

echo "warm-up complete: $(du -sh "$YARN_CACHE_FOLDER" | cut -f1) of yarn cache"
