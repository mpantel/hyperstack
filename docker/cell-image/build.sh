#!/usr/bin/env bash
# Build (and optionally push) the dependency image for one cell (#57).
#
#   HYPERSTACK_CELL=rails61-react16 docker/cell-image/build.sh [--push]
#
# Build args come from `rake hyperstack:cell:env`, i.e. from
# supported_versions.yml -- the same table the test run reads and the
# cell-contract spec (!83) verifies at runtime. Adding a cell stays a one-file
# change: define it in the table and this picks it up.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CELL="${HYPERSTACK_CELL:?set HYPERSTACK_CELL}"
IMAGE="${CELL_IMAGE_PREFIX:-registry.ru.aegean.gr/ru/hyperstack/cell}:${CELL}"
CONTEXT="$ROOT/tmp/cell-context"

# Resolve the cell's env, then turn each exported var into a --build-arg. Vars
# the cell does not set are simply absent, and the Dockerfile's empty defaults
# mean "use the gemspec default" -- matching how the test jobs behave.
eval "$(cd "$ROOT" && HYPERSTACK_CELL="$CELL" rake hyperstack:cell:env)"

ARGS=()
for v in RBENV_VERSION RAILS_VERSION OPAL_VERSION OPAL_RAILS_VERSION REACT_RAILS_VERSION; do
  if [ -n "${!v:-}" ]; then ARGS+=(--build-arg "$v=${!v}"); fi
done

# Bundle exactly what CI bundles, not every directory with a Gemfile. The
# COMPONENT values in .gitlab-ci.yml are the definition; hyper-console has a
# Gemfile but is never tested, and its multiple global `source` lines are a hard
# error under Bundler 4 ("Each source after the first must include a block"),
# which failed the first build.
COMPONENTS="$(grep -oE 'COMPONENT: [a-z0-9-]+' "$ROOT/.gitlab-ci.yml" | awk '{print $2}' | sort -u | tr '\n' ' ')"
echo "components: $COMPONENTS"

"$ROOT/docker/cell-image/prepare-context.sh" "$CONTEXT"

echo "building $IMAGE"
printf '  %s\n' "${ARGS[@]:-(no cell overrides; gemspec defaults)}"

# --cache-from the published tag: unchanged layers are reused, so this can run
# unconditionally and is nearly free when dependencies have not moved. That is
# what makes "on demand" work without having to detect whether a rebuild is due.
docker build \
  --cache-from "$IMAGE" \
  --build-arg "HYPERSTACK_COMPONENTS=$COMPONENTS" \
  ${BASE_IMAGE:+--build-arg "BASE_IMAGE=$BASE_IMAGE"} \
  "${ARGS[@]}" \
  -t "$IMAGE" \
  -f "$ROOT/docker/cell-image/Dockerfile" \
  "$CONTEXT"

if [ "${1:-}" = "--push" ]; then
  echo "pushing $IMAGE"
  docker push "$IMAGE"
fi
