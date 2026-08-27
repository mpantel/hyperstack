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

# The -n test is no longer what keeps an empty version selector out of a gemspec
# -- Hyperstack.version_selector treats blank as unset (#78). It still matters for
# RBENV_VERSION, whose ARG carries a real default that an empty --build-arg would
# override with nothing; for the rest it is now belt-and-braces.
ARGS=()
for v in RBENV_VERSION RAILS_VERSION OPAL_VERSION OPAL_RAILS_VERSION OPAL_SPROCKETS_VERSION \
         REACT_RAILS_VERSION SQLITE3_VERSION HYPERSTACK_JS_PIPELINE; do
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
  # Re-authenticate first. The credential the CI job minted in its before_script
  # is no longer accepted by the time a build of this length finishes: every
  # layer uploads and then the push ends in
  #   unauthorized: HTTP Basic: Access denied. If a password was provided for Git
  #   authentication, the password was incorrect or you're required to use a
  #   token instead
  # The cutoff is ~5 minutes (the registry token's TTL). Pipeline 6675 shows it
  # exactly -- pushes reached at 273s succeeded, at 463s / 547s / 547s / 552s all
  # four failed -- and 6665, before the warm-up layer made the build ~2 minutes
  # longer, pushed at 199-282s and never hit it. So this was always latent; #75
  # simply made the build long enough to cross the line.
  #
  # Guarded on CI_REGISTRY_PASSWORD so a local `build.sh --push` keeps using
  # whatever `docker login` the developer already did.
  if [ -n "${CI_REGISTRY_PASSWORD:-}" ]; then
    echo "re-authenticating with ${CI_REGISTRY} before push"
    echo "$CI_REGISTRY_PASSWORD" | docker login -u "${CI_REGISTRY_USER:-gitlab-ci-token}" --password-stdin "${CI_REGISTRY:?CI_REGISTRY not set}"
  fi
  echo "pushing $IMAGE"
  docker push "$IMAGE"
fi
