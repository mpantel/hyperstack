# Opal `native`: `Hash.new(map)` leaks the source as the default value

**Affects:** Opal 1.8.x (`stdlib/native.rb`). Surfaced via Hyperstack issue #24.

## Summary

When the `native` stdlib is loaded, `Hash.new(source)` is overridden to
*populate* a new Hash from `source`'s entries. For a `source` whose constructor
is `Object`/`undefined` it copies the keys and `return self`s. For a `source`
that is a `Map` (which, in Opal 1.8, is what backs **every** Ruby Hash) it copies
the keys but **does not** `return self`. Execution falls through to the core MRI
`Hash#initialize`, which sets `source` as the new hash's **default value**.

The hash therefore ends up correctly populated *and* with a non-nil default, so
every **missing** key returns the whole `source` hash (a truthy object) instead
of `nil`.

## Reproduction

```ruby
require 'native'

src  = { 'a' => 1 }
copy = Hash.new(src)

copy['a']        # => 1            (populated correctly)
copy['missing']  # => { 'a' => 1 } # BUG: expected nil
copy.default     # => { 'a' => 1 } # BUG: expected nil
copy.key?('missing') # => false    (so [] and key? disagree)
```

See [`native_hash_new_from_map_spec.rb`](./native_hash_new_from_map_spec.rb) for
a self-contained spec (Opal + `native` only, no Hyperstack).

## Root cause

`stdlib/native.rb`, `Hash#initialize`: the `Object` branch ends with
`return self`; the `Map` branch does not, so it falls through to
`_initialize(defaults, &block)` (MRI), which assigns the default value.

## Fix

Add the missing `return self` to the `Map` branch — see
[`native-hash-new-from-map-leaks-default.patch`](./native-hash-new-from-map-leaks-default.patch).

## Why this matters downstream (Hyperstack)

Hyperstack passes Ruby Hash params to React; on the way back they are rebuilt via
`Hash.new(map)`. With the bug, `params[:some_hash][:absent_key]` returns the
whole hash instead of `nil`. In hyperstack-addons this made the `Pager` believe
every column had a `:filter`, then crash in `set_filter_value`
(`undefined method 'to_sym' for nil`).

Until the upstream fix ships, hyper-component ships an equivalent runtime
workaround in
`lib/hyperstack/internal/component/native_to_hash.rb` (reopens `Hash#initialize`
and clears the leaked default after a Map-sourced construction).
