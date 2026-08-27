#!/usr/bin/env bash
# Stage a MINIMAL build context for the cell dependency image (#57).
#
# The point is Docker layer caching. If the context were the whole repo, the
# COPY layer -- and therefore `bundle install` -- would be invalidated by every
# commit, and the image would rebuild from scratch constantly. bundle install
# only needs the Gemfiles, the gemspecs, and whatever those gemspecs `require`
# (each gem's version.rb). Staging just those means the expensive layer is
# invalidated by DEPENDENCY changes and nothing else.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$ROOT/tmp/cell-context}"

rm -rf "$OUT"
mkdir -p "$OUT/ruby"

cp "$ROOT/HYPERSTACK_VERSION" "$OUT/" 2>/dev/null || true
cp "$ROOT/ruby/version.rb"    "$OUT/ruby/" 2>/dev/null || true

for dir in "$ROOT"/ruby/*/; do
  gem="$(basename "$dir")"
  [ -f "$dir/Gemfile" ] && [ -f "$dir/$gem.gemspec" ] || continue
  mkdir -p "$OUT/ruby/$gem"
  cp "$dir/Gemfile" "$dir/$gem.gemspec" "$OUT/ruby/$gem/"
  # Deliberately NOT Gemfile.lock: it is gitignored for these gems (only
  # ruby/examples/* commit one), so any lockfile on disk is local developer
  # state that would not exist in a clean CI checkout. Copying it would bake one
  # machine's resolution into the image and make the build unreproducible.
  # gemspecs `require` their own version.rb, so it must be present for the
  # gemspec to even evaluate.
  ( cd "$dir" && find lib -name 'version.rb' -print0 2>/dev/null ) | while IFS= read -r -d '' v; do
    mkdir -p "$OUT/ruby/$gem/$(dirname "$v")"
    cp "$dir/$v" "$OUT/ruby/$gem/$v"
  done
done

# The image also bakes the gems `rake spec:prepare` installs into GEM_HOME
# (#73), and it takes the list from this file so the pins are defined once. It
# is a dependency definition like the Gemfiles above -- editing it SHOULD
# invalidate the image, and nothing else in the repo touches it.
mkdir -p "$OUT/ruby/rails-hyperstack"
cp "$ROOT/ruby/rails-hyperstack/spec_prepare_gems.rb" "$OUT/ruby/rails-hyperstack/"

# The warm-up step that generates a throwaway app to fill GEM_HOME and the yarn
# cache (#75). Same argument as above: an input to the image, and to nothing
# else, so it belongs in the context and should invalidate the build.
mkdir -p "$OUT/docker/cell-image"
cp "$ROOT/docker/cell-image/warm-app.sh" "$OUT/docker/cell-image/"

echo "staged $(find "$OUT" -type f | wc -l) files into $OUT"
