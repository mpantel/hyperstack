module Hyperstack
  module Internal
    module Component
      # Convert a native React props/state object into a Ruby Hash.
      #
      # Historically hyper-component used `Hash.new(native)`, relying on the
      # `native` stdlib reopening `Hash#initialize` to populate the hash from the
      # JS object's keys. Under Opal 1.8 that override only runs when the native
      # object's constructor is `Object`/`undefined` (or it is a `Map`); React's
      # props/state objects no longer match, so the core MRI `Hash#initialize`
      # runs instead. That sets the hash's *default value* to the native object
      # and leaves the hash empty, so any missing key returns the (truthy) native
      # object rather than `nil` (issue #24).
      #
      # Copying the native object's own enumerable properties into a plain object
      # literal guarantees the `native` bridge takes its populate branch, yielding
      # a real Hash with a `nil` default and the same recursive key conversion as
      # before.
      def self.native_to_hash(native)
        return {} if `#{native} == null`

        Hash.new(`Object.assign({}, #{native})`)
      end
    end
  end
end
