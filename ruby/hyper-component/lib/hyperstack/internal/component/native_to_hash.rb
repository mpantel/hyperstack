# Fix for an Opal 1.8 `native` stdlib bug that breaks Hyperstack params/state.
#
# `require 'native'` (loaded before this file) reopens `Hash#initialize` so that
# `Hash.new(source)` *populates* a real Hash from `source`'s entries instead of
# using `source` as the hash's default value. It has two populate branches:
#
#   * source.constructor === Object/undefined  -> copy keys, then `return self`
#   * source instanceof Map (an Opal 1.8 Hash) -> copy keys, but NO `return self`
#
# The missing `return self` makes the Map branch fall through to the core MRI
# `Hash#initialize`, which sets the hash's *default value* to `source`. The hash
# ends up correctly populated, yet every *missing* key returns the whole source
# hash (a truthy value) instead of `nil`.
#
# This bites Hyperstack hard: any Ruby Hash passed as a param arrives as a
# Map-backed Opal Hash nested in the native props, and is rebuilt via
# `Hash.new(map)` (directly on re-render, or while converting props/state). So
# e.g. `columns[:some_col][:missing_key]` returned the whole column hash, which
# made addons' Pager think every column had a `:filter` and crash in
# `set_filter_value` (issue #24, deep case).
#
# Fix: re-open `Hash#initialize`; when the source is a Map, let the native impl
# populate as usual, then clear the leaked default back to `nil`. Entries (and
# their original key types) are untouched, and nested Map values are corrected
# recursively because the native populate path itself calls `Hash.new` on them.
class Hash
  alias_method :_hyperstack_pre_map_fix_initialize, :initialize

  def initialize(defaults = undefined, &block)
    source_is_map = `#{defaults} != null && typeof Map !== 'undefined' && #{defaults} instanceof Map`
    result = _hyperstack_pre_map_fix_initialize(defaults, &block)
    self.default = nil if source_is_map
    result
  end
end

module Hyperstack
  module Internal
    module Component
      # Convert a native React props/state object into a Ruby Hash.
      #
      # React props/state objects don't have an `Object`/`Map` constructor, so
      # `Hash.new(native)` would hit the MRI branch and leave an empty hash with a
      # native default. Copying the own-enumerable properties into a plain object
      # literal first guarantees the `native` bridge takes its `Object` populate
      # branch; nested Map-backed Opal Hashes are then converted (and their
      # defaults corrected by the patch above) recursively.
      def self.native_to_hash(native)
        return {} if `#{native} == null`

        Hash.new(`Object.assign({}, #{native})`)
      end
    end
  end
end
