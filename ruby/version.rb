module Hyperstack
  # Version: a plain point release in the historical `1.0.alpha1.<n>` series.
  #
  # Releases up to 1.0.alpha1.8.34.18.61.1614.6 appended the hyperstack-addons
  # compatibility scheme <ruby>.<opal>.<rails>.<react major+minor>.<patch>, because
  # one build served exactly one combination and the version string was the only
  # record of which. That is no longer true: a single gem set is now tested across
  # the whole matrix in supported_versions.yml (Rails 6.1-8.1, Ruby 3.4-4.0,
  # React 16-19), so no single combination can be encoded here honestly.
  #
  # supported_versions.yml is the compatibility statement. Hyperstack::SupportedVersions
  # checks a booting app against it, and `rake hyperstack:config:check` does the same
  # from the command line. (#51)
  VERSION = '1.0.alpha1.9'
end
