# frozen_string_literal: true

module Hyperstack
  # A version selector lets the matrix pin a dependency for one cell
  # (`RAILS_VERSION=6.1.7.10 bundle install`) while a plain checkout resolves the
  # gemspec's own range. The gemspecs used to select like this:
  #
  #   *(ENV['RAILS_VERSION'] ? [ENV['RAILS_VERSION']] : ['>= 5.0.0', '< 7.0'])
  #
  # and '' is truthy in Ruby, so a variable that was exported but EMPTY took the
  # ENV branch and produced the requirement [''] -- `bundle install` then aborts
  # with "Illformed requirement", from a gemspec, pointing nowhere near the cell
  # definition that caused it.
  #
  # Blank means unset here, so both consumers of supported_versions.yml are
  # covered: the image build (docker/cell-image/build.sh passes only non-empty
  # --build-args) and the test jobs (`eval "$(rake hyperstack:cell:env)"`, which
  # emits one export per key in the cell's env block and maps a YAML nil to '').
  # Only the first of those ever had a guard. (#78)
  #
  # Not in any gem's spec.files on purpose: gemspec evaluation only ever happens
  # in the source tree (`gem build`, or Bundler on a path gem), and an installed
  # gem carries the serialized spec with the dependencies already resolved.
  def self.version_selector(name, *defaults)
    override = ENV[name].to_s.strip
    override.empty? ? defaults : [override]
  end

  # The react-rails gemspec range, so the Gemfiles ask the same question the
  # gemspec answers rather than restating the bounds.
  REACT_RAILS_DEFAULTS = ['>= 2.4.0', '< 4.0'].freeze

  # The published react-rails 2.x releases. A requirement admits "some 2.x" only
  # if it admits one of these, and there is no way to ask Gem::Requirement that
  # directly -- `~> 2.6.0` and `~> 3.3` both reject a synthetic 2.999999.
  LEGACY_POOL_REACT_RAILS = %w[
    2.4.0 2.5.0 2.6.0 2.6.1 2.6.2 2.7.0 2.7.1
  ].freeze

  # Does the react-rails this cell selected still need connection_pool 2.x?
  #
  # connection_pool 3.0 made ConnectionPool#initialize keyword-only:
  #
  #   2.5.5   def initialize(options = {}, &block)
  #   3.0.2   def initialize(timeout: 5, size: 5, auto_reload_after_fork: true, name: nil, &)
  #
  # react-rails builds its server-renderer pool in
  # `React::ServerRendering.reset_pool`, and the call site changed between
  # majors:
  #
  #   2.6.2 / 2.7.1   ConnectionPool.new(options)     -- positional hash
  #   3.3.1           ConnectionPool.new(**options)   -- keyword args
  #
  # so on connection_pool 3.x the 2.x line dies with "wrong number of arguments
  # (given 1, expected 0)" the first time anything prerenders, while 3.3.1 -- which
  # passes exactly { size:, timeout: }, both real keywords -- is fine.
  #
  # The pin used to be a flat `gem 'connection_pool', '< 3.0'` in all nine
  # Gemfiles, so seven of the ten cells were held on connection_pool 2.5.5 for a
  # constraint belonging to the other three. REACT_RAILS_VERSION is already
  # per-cell in supported_versions.yml, so ask it. (#122)
  #
  # Deliberately conservative: the pin is lifted only when the selector CANNOT
  # resolve to a 2.x. The default range admits both majors, so a plain checkout
  # keeps the pin and only a cell that says `~> 3.3` floats.
  def self.legacy_connection_pool?
    selector = Gem::Requirement.new(
      version_selector('REACT_RAILS_VERSION', *REACT_RAILS_DEFAULTS)
    )
    LEGACY_POOL_REACT_RAILS.any? do |version|
      selector.satisfied_by?(Gem::Version.new(version))
    end
  end

  # The requirement to give `gem 'connection_pool'`: empty (unpinned) once the
  # selected react-rails can take connection_pool 3.x.
  def self.connection_pool_selector
    legacy_connection_pool? ? ['< 3.0'] : []
  end
end
