# frozen_string_literal: true

# Ruby 3.4 "chilled string" deprecations: several unmaintained gems in the test
# toolchain mutate the (chilled) string returned by `Symbol#to_s`, so every spec
# run floods stderr with thousands of lines like
#   .../<gem>.rb:NN: warning: string returned by :foo.to_s will be frozen in the future
# The offending gems are all at their latest release with no fix upstream:
#   - parser        (via unparser, when hyper-spec re-parses each mount/evaluate block)
#   - em-websocket  (the in-process websocket server used by the sync specs)
#   - unicode_utils
# Drop only those specific deprecation lines from those specific gems; every other
# warning — including any "will be frozen" coming from Hyperstack or user code —
# still passes through untouched.
#
# Removal: this is a temporary workaround. To re-expose the warnings (e.g. to check
# whether the gems have been fixed/replaced, or to drop a gem from GEMS below),
# run the suite with HYPER_SPEC_SHOW_FROZEN_WARNINGS=1. Once none of GEMS emit the
# deprecation any longer, delete this file and its require in hyper-spec.rb.
module HyperSpec
  module WarningFilter
    # The unmaintained, latest-release gems that mutate a chilled `Symbol#to_s`.
    GEMS = %w[parser em-websocket unicode_utils].freeze
    FROZEN_DEPRECATION = /string returned by .* will be frozen in the future/
    THIRD_PARTY = %r{/gems/(?:#{Regexp.union(GEMS)})-\d}

    def warn(message, category: nil)
      return if message.is_a?(String) &&
                message.match?(FROZEN_DEPRECATION) &&
                message.match?(THIRD_PARTY)

      super
    end
  end
end

# Opt-out escape hatch so the warnings can be re-exposed without a code change.
Warning.extend(HyperSpec::WarningFilter) unless ENV['HYPER_SPEC_SHOW_FROZEN_WARNINGS']
