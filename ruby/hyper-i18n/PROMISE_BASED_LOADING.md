# Promise-Based Translation Loading

**Date**: 2025-11-12
**Added to**: Hyperstack::Internal::I18n

## Problem

The existing `t()` method returns immediately with a default value while triggering async translation loading in the background. This creates race conditions where components render with untranslated content, then flash/re-render when translations arrive.

### Previous Behavior

```ruby
t('some.key')  # Returns '' or opts[:default] immediately
               # Triggers async Translate.run() in background
               # Updates Store when complete (causes re-render)
```

**Issues**:
- No way to wait for translations to load
- Flash of untranslated content (FOUC)
- Components must use `sleep` in tests to wait for translations
- Modal closures and state loss during re-renders

## Solution

Added two new methods to `Hyperstack::Internal::I18n`:

### 1. `t_async(attribute, opts = {})`

Returns a promise that resolves when the translation is loaded.

```ruby
Hyperstack::Internal::I18n.t_async('user.greeting')
  .then { |translation| puts translation }
```

**Behavior**:
- If translation already cached: Returns `Promise.resolve(cached_value)`
- If not cached: Returns promise from `Translate.run()` that resolves when loaded
- On server: Returns synchronous value wrapped in resolved promise

### 2. `preload(keys, opts = {})`

Preloads multiple translations and returns promise that resolves when **all** are loaded.

```ruby
Hyperstack::Internal::I18n.preload(['key1', 'key2', 'key3'])
  .then { puts "All translations loaded!" }
```

**Behavior**:
- Creates array of promises (one per key)
- Uses `Promise.when(*promises)` to wait for all
- Returns array of translations when complete

## Usage in Components

### Before (Race Condition)

```ruby
def index_render
  # Trigger translation loads (async)
  columns.each { |_, col| t(col[:description]) }

  # Render immediately (shows untranslated content)
  Pager(...) do
    # Column headers show Greek keys initially
    # Flash to English when translations arrive
  end
end
```

### After (Promise-Based)

```ruby
def index_render
  @translations_loading = true if RUBY_ENGINE == 'opal'

  # Collect keys
  keys = columns.map { |_, col| col[:description] }

  # Wait for all translations to load
  Hyperstack::Internal::I18n.preload(keys).then do
    @translations_loading = false
    force_update!  # Trigger re-render with translations
  end

  # Show loading state while waiting
  if @translations_loading
    DIV { "Loading translations..." }
  else
    Pager(...) do
      # Column headers show English immediately
    end
  end
end
```

## Implementation Details

### Client-Side (Opal)

```ruby
def self.t_async(attribute, opts = {})
  if Store.translations[attribute]
    Promise.resolve(Store.translations[attribute])
  else
    Translate.run(attribute: attribute, opts: opts)
      .then do |translation|
        Store.translations[attribute] = translation
        Store.mutate.translations(Store.translations)
        translation
      end
  end
end
```

### Server-Side (Ruby)

```ruby
def self.t_async(attribute, opts = {})
  Promise.resolve(::I18n.t(attribute, **opts.symbolize_keys))
end
```

## Benefits

1. **No Flash of Untranslated Content**: Components can wait for translations before rendering
2. **No Sleep in Tests**: Tests can wait for actual promises instead of arbitrary delays
3. **Composable**: Multiple preloads can be chained with `.then`
4. **Backward Compatible**: Existing `t()` method unchanged
5. **Isomorphic**: Works on both client and server

## Real-World Usage

### Pager Translation Fix

**File**: `app/hyperstack/shared/pager_translation_fix.rb`

```ruby
def preload_translations_once
  translation_keys = columns.map { |_, col| col[:description] }

  @translations_loading = true if RUBY_ENGINE == 'opal'

  Hyperstack::Internal::I18n.preload(translation_keys).then do
    @translations_loading = false
    force_update!
  end
end

def index_render
  if @translations_loading
    DIV { "Loading translations..." }
  else
    Pager(...) { ... }
  end
end
```

**Result**: Pager waits for translations, then renders once with correct English text. No flash, no modal closures.

## Testing

### Before (Unreliable)

```ruby
it "shows translated text" do
  mount 'MyComponent'
  sleep 2  # Wait for async translations (arbitrary delay)
  expect(page).to have_content('Project')
end
```

### After (Promise-Based)

```ruby
it "shows translated text" do
  mount 'MyComponent'
  # Component shows "Loading translations..." while waiting
  # Then renders with translated content
  expect(page).to have_content('Project', wait: 10)
  # Capybara wait handles the async nature properly
end
```

## Performance Considerations

- **Cached translations**: Instant (resolved promise)
- **Uncached translations**: Single AJAX request per key
- **Batch preloading**: All AJAX requests fire in parallel via `Promise.when`
- **Re-renders**: Only one re-render after all translations load (vs multiple partial re-renders)

## Future Enhancements

1. **Batch Translate Operation**: Single server request for multiple keys
   ```ruby
   Translate.run(attributes: ['key1', 'key2', 'key3'])
   ```

2. **Translation Prefetching**: Preload likely-needed translations on page load
   ```ruby
   before_first_mount do
     Hyperstack::Internal::I18n.preload(common_keys)
   end
   ```

3. **Loading Indicators**: Standardized loading component
   ```ruby
   WithTranslations(keys: ['key1', 'key2']) do |translations|
     # Renders when translations ready
   end
   ```

## Migration Guide

### For Application Developers

**No changes required** - existing `t()` calls work as before.

**Optional improvements**:
```ruby
# Old (works but flashes)
def render
  DIV { t('greeting') }  # Shows '', then translation
end

# New (no flash)
def render
  if @loading
    DIV { "Loading..." }
  else
    DIV { t('greeting') }
  end
end

before_mount do
  @loading = true
  Hyperstack::Internal::I18n.t_async('greeting').then do
    @loading = false
    force_update!
  end
end
```

### For Framework Developers

Use `preload()` in base components (Index, Pager, etc.) to eliminate FOUC globally:

```ruby
class Base::Index
  def index_render
    preload_translations_once

    if @translations_loading
      loading_indicator
    else
      actual_content
    end
  end

  def preload_translations_once
    return if @translations_preloaded
    @translations_preloaded = true
    @translations_loading = true

    keys = collect_all_translation_keys
    Hyperstack::Internal::I18n.preload(keys).then do
      @translations_loading = false
      force_update!
    end
  end
end
```

## Changelog

- **2025-11-12**: Initial implementation
  - Added `Hyperstack::Internal::I18n.t_async()`
  - Added `Hyperstack::Internal::I18n.preload()`
  - Updated `pager_translation_fix.rb` to use promise-based loading
  - Eliminated race conditions in Index components
  - Removed `sleep 2` workarounds from tests
