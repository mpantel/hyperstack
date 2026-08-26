# Dependency image for one matrix cell (#57).
#
# Bakes `local_gems` -- every gem's bundle, including compiled native extensions
# -- so jobs stop paying to fetch and unpack it. Measured on job 39544:
# restore_cache is 57.9s per job against a warm `bundle install` of 8.9s, i.e.
# most of the setup cost is transferring compiled artifacts that never changed.
# Across a 48-job pipeline that is ~46 minutes of runner time.
#
# FROM base24:yjit for now, which already carries the tools AND the rubies, so
# this needs no ru/infrastructure change to prove out. The eventual split
# (base24:tools + a project-owned ruby layer) is recorded on #57; switching the
# FROM is then a one-line change here.
ARG BASE_IMAGE=registry.ru.aegean.gr/ru/infrastructure/base24:yjit
FROM ${BASE_IMAGE}

# Cell parameters. These are exactly the values `rake hyperstack:cell:env`
# resolves from supported_versions.yml, so the image is built from the same
# single source of truth the test run uses -- no second place for the matrix to
# drift. An empty value means "take the gemspec default", matching a cell whose
# env omits it.
ARG RBENV_VERSION=3.4.9
ARG RAILS_VERSION=""
ARG OPAL_VERSION=""
ARG OPAL_RAILS_VERSION=""
ARG REACT_RAILS_VERSION=""

ENV RBENV_VERSION=${RBENV_VERSION} \
    RAILS_VERSION=${RAILS_VERSION} \
    OPAL_VERSION=${OPAL_VERSION} \
    OPAL_RAILS_VERSION=${OPAL_RAILS_VERSION} \
    REACT_RAILS_VERSION=${REACT_RAILS_VERSION}

USER root
RUN mkdir -p /hyperstack && chown -R ubuntu:ubuntu /hyperstack
USER ubuntu
WORKDIR /hyperstack

# Only the dependency-defining files (see prepare-context.sh). Copying the whole
# repo would invalidate this layer -- and the bundle below -- on every commit.
COPY --chown=ubuntu:ubuntu . /hyperstack/

# The gemspecs call `git ls-files` for spec.files. Without a repo that errors and
# the gemspec fails to evaluate, so give it an empty one: spec.files is
# irrelevant to dependency resolution, which is all this image is for.
RUN git init -q . && git config user.email ci@hyperstack && git config user.name ci

# One `local_gems` shared by every gem, exactly as CI does it
# (`bundle config set --local path ../../local_gems`).
RUN set -eux; \
    gem install bundler -v '~> 4.0'; \
    for dir in ruby/*/; do \
      gem="$(basename "$dir")"; \
      [ -f "$dir/Gemfile" ] || continue; \
      cd "/hyperstack/$dir"; \
      bundle config set --local path ../../local_gems; \
      bundle install --jobs=3 --retry=3; \
      cd /hyperstack; \
    done; \
    du -sh /hyperstack/local_gems

# Jobs symlink this in place of restoring the cache.
ENV HYPERSTACK_PREBAKED_GEMS=/hyperstack/local_gems
