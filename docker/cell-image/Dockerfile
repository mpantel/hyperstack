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
# Set instead of OPAL_RAILS_VERSION by a cell that reaches sprockets through
# opal-sprockets directly -- opal-rails 2.x cannot resolve on Rails 8. (#20)
ARG OPAL_SPROCKETS_VERSION=""
ARG REACT_RAILS_VERSION=""
# Rails 8 needs sqlite3 2.x; the gemspecs pin `< 2` for the Rails 6.1 cells.
ARG SQLITE3_VERSION=""
# No cell sets this today -- the gemspecs' own `< 2` is what pins pg (#102).
# It is plumbed through anyway so that pinning pg per cell stays a one-line
# change in supported_versions.yml: a selector the image build does not pass
# resolves one bundle at build time and a different one in the job.
ARG PG_VERSION=""
# Which JS pipeline this cell scaffolds with. Unlike the version selectors this
# one is a plain string with a safe default (spec_prepare_gems.rb derives it from
# the Rails version when unset), so it can be exported unconditionally. The
# warm-up layer needs it to know whether `webpacker:install` is what fills the
# yarn cache. (#75)
ARG HYPERSTACK_JS_PIPELINE=""
# The gems CI actually bundles, passed in from .gitlab-ci.yml's COMPONENT values
# by build.sh. Not "every directory with a Gemfile": hyper-console has one but is
# never tested, and its Gemfile has multiple global sources, which Bundler 4
# rejects outright.
ARG HYPERSTACK_COMPONENTS=""

# An empty version selector is safe to export: the gemspecs read them through
# Hyperstack.version_selector (ruby/version_selector.rb), which treats blank as
# unset and falls back to the gemspec default. That guard used to live here, as a
# loop that unset every empty variable before each RUN that evaluates a gemspec,
# on the theory that '' is truthy in Ruby -- true, but the place to know it is
# the selector, not every consumer of the table. (#78)
ENV RBENV_VERSION=${RBENV_VERSION}

USER root
RUN mkdir -p /hyperstack && chown -R ubuntu:ubuntu /hyperstack
USER ubuntu
WORKDIR /hyperstack

# Only the dependency-defining files (see prepare-context.sh). Copying the whole
# repo would invalidate this layer -- and the bundle below -- on every commit.
#
# Deliberately NOT `COPY . /hyperstack/`: the context also carries the warm-up
# script (#75), which is a build *procedure*, not a dependency. Copying it here
# would put it in the same layer as the Gemfiles and make every edit to it redo
# the ~370s bundle below. It gets its own COPY, after the expensive layers.
COPY --chown=ubuntu:ubuntu HYPERSTACK_VERSION /hyperstack/
COPY --chown=ubuntu:ubuntu ruby /hyperstack/ruby

# The gemspecs call `git ls-files` for spec.files. Without a repo that errors and
# the gemspec fails to evaluate, so give it an empty one: spec.files is
# irrelevant to dependency resolution, which is all this image is for.
RUN git init -q . && git config user.email ci@hyperstack && git config user.name ci

# One `local_gems` shared by every gem, exactly as CI does it
# (`bundle config set --local path ../../local_gems`).
RUN set -eux; \
    env | grep -E '^(RBENV|RAILS|OPAL|REACT|SQLITE3|PG)_' || echo 'no version selectors set (gemspec defaults)'; \
    gem install bundler -v '~> 4.0'; \
    for gem in ${HYPERSTACK_COMPONENTS}; do \
      [ -f "ruby/$gem/Gemfile" ] || continue; \
      cd "/hyperstack/ruby/$gem"; \
      bundle config set --local path ../../local_gems; \
      bundle install --jobs=3 --retry=3; \
      cd /hyperstack; \
    done; \
    du -sh /hyperstack/local_gems

# Jobs symlink this in place of restoring the cache.
ENV HYPERSTACK_PREBAKED_GEMS=/hyperstack/local_gems

# The OTHER gems a job installs: the ones rails-hyperstack's `rake spec:prepare`
# puts in GEM_HOME before generating the test app (#73). They are not part of any
# bundle -- spec:prepare shells out under `Bundler.with_unbundled_env` and runs
# plain `gem install` -- so `local_gems` above never held them and the cache
# never could. Measured on rails61-react17, they are 284-523s of every job, most
# of it nokogiri 1.15.6 building from source, once per job, forever.
#
# This image runs as `ubuntu` on rbenv's GEM_HOME, which is precisely where
# spec:prepare looks, so installing them here makes its `gem install` calls
# no-ops. The version list is NOT repeated here: spec_prepare_gems.rb prints the
# commands and spec:prepare consumes the same list, so there is no second place
# for the pins to drift (#51). It resolves the rails version from this cell's
# freshly-installed bundle, so image and job install the same rails.
RUN set -eux; \
    cd /hyperstack; \
    ruby ruby/rails-hyperstack/spec_prepare_gems.rb > /tmp/prepare-gems.sh; \
    cat /tmp/prepare-gems.sh; \
    sh -eux /tmp/prepare-gems.sh; \
    rm -f /tmp/prepare-gems.sh; \
    ruby ruby/rails-hyperstack/spec_prepare_gems.rb --verify

# Jobs read this as "the image carries spec:prepare's gems". spec:prepare aborts
# if it is set and one of them is missing, rather than quietly rebuilding
# nokogiri for three minutes and looking like a slow success -- the same rule
# #57 applied to a missing prebaked bundle.
ENV HYPERSTACK_PREBAKED_SPEC_GEMS=1

# Everything the generated app installs *implicitly* -- its own ~76-gem bundle
# into GEM_HOME, and (Webpacker cells) the npm tree webpacker:install downloads.
# warm-app.sh generates a throwaway app exactly as spec:prepare will, lets it
# install, then deletes the app and keeps what it left behind. ~95s off every
# rails61 job; see the table in that script. (#75)
#
# HYPERSTACK_JS_PIPELINE needed no guard even before #78: spec_prepare_gems.rb,
# which warm-app.sh asks which pipeline this cell is, already reads it as
# `ENV['HYPERSTACK_JS_PIPELINE'] unless ...to_s.empty?`.
ENV HYPERSTACK_PREBAKED_YARN_CACHE=/hyperstack/yarn-cache
COPY --chown=ubuntu:ubuntu docker /hyperstack/docker
RUN set -eux; \
    YARN_CACHE_FOLDER="$HYPERSTACK_PREBAKED_YARN_CACHE" \
      bash /hyperstack/docker/cell-image/warm-app.sh; \
    du -sh /hyperstack/yarn-cache
