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
end
