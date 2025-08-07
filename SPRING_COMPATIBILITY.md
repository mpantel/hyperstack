# Spring Compatibility with Rails 6.1 + Ruby 3.2+

## Issue
Spring 4.3.0 has compatibility issues with Rails 6.1.7.10 + Ruby 3.2.9, causing this error:
```
Rails::Application is abstract, you cannot instantiate it directly. (RuntimeError)
```

## Solutions

### Option 1: Disable Spring (Recommended)
For Rails commands that fail with Spring, use:
```bash
DISABLE_SPRING=1 bundle exec rails generate hyperstack:install
DISABLE_SPRING=1 bundle exec rails server
DISABLE_SPRING=1 bundle exec rspec
```

### Option 2: Stop Spring Before Commands
```bash
spring stop
bundle exec rails generate hyperstack:install
```

### Option 3: Update Spring (if possible)
```ruby
# In Gemfile
gem 'spring', '~> 4.4' # or latest compatible version
```
Then run:
```bash
bundle update spring
```

### Option 4: Remove Spring (for development)
```ruby
# In Gemfile, comment out or remove:
# gem 'spring'
# gem 'spring-watcher-listen'
```

## Fixed Issues
✅ **Logger Compatibility**: Fixed `ActiveSupport::LoggerThreadSafeLevel::Logger (NameError)`
✅ **Generator Integration**: Hyperstack generators now include compatibility fixes
✅ **Initialization**: Both server_side_auto_require and generators include fixes

## Testing
- With `DISABLE_SPRING=1`: ✅ All generators work
- With Spring enabled: ⚠️ May require version updates or disabling

## Recommendation
For Ruby 3.2+ and Rails 6.1+, use `DISABLE_SPRING=1` prefix for Rails commands until Spring compatibility is resolved.