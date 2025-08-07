# Node.js Compatibility with Rails-Hyperstack

## Issue
When running specs with Node.js 17+ (including version 20.19.4), you may encounter this error:
```
Error: error:0308010C:digital envelope routines::unsupported
    at new Hash (node:internal/crypto/hash:79:19)
    at Object.createHash (node:crypto:139:10)
    at CompressionPlugin.taskGenerator
```

This occurs because Node.js 17+ removed support for the legacy OpenSSL provider that webpack 4 depends on.

## Solution

### Method 1: Use Legacy OpenSSL Provider (Recommended)
Prefix your Rails commands with `NODE_OPTIONS='--openssl-legacy-provider'`:

```bash
# For running specs
NODE_OPTIONS='--openssl-legacy-provider' bundle exec rspec

# For webpack compilation
NODE_OPTIONS='--openssl-legacy-provider' bundle exec rails webpacker:compile

# For running Rails server
NODE_OPTIONS='--openssl-legacy-provider' bundle exec rails server
```

### Method 2: Export Environment Variable
Set the environment variable once in your shell session:

```bash
export NODE_OPTIONS='--openssl-legacy-provider'
bundle exec rspec
bundle exec rails webpacker:compile
bundle exec rails server
```

### Method 3: Add to Package.json (Already Done)
The test_app/package.json has been updated with scripts that include the legacy provider:

```json
{
  "scripts": {
    "webpack": "NODE_OPTIONS='--openssl-legacy-provider' webpack",
    "webpack-dev-server": "NODE_OPTIONS='--openssl-legacy-provider' webpack-dev-server"
  }
}
```

### Method 4: Downgrade Node.js (Alternative)
If the above solutions don't work, you can use Node.js 16.x:

```bash
# Using nvm
nvm install 16
nvm use 16
```

## Technical Details
- **Root Cause**: Node.js 17+ deprecated legacy OpenSSL providers that webpack 4 relies on
- **Affected**: webpack 4.x with Node.js 17+
- **Fix**: Use `--openssl-legacy-provider` flag to enable deprecated crypto algorithms
- **Future**: Upgrade to webpack 5+ for proper Node.js 17+ support

## Testing
✅ **Verified**: Webpack compilation works with `NODE_OPTIONS='--openssl-legacy-provider'`
✅ **Verified**: Rails specs run without crypto errors using the legacy provider
✅ **Package.json**: Updated with scripts that include the legacy provider option

## Recommendation
For immediate compatibility with Node.js 20.19.4 and webpack 4.46.0, use the `NODE_OPTIONS='--openssl-legacy-provider'` prefix for all Rails/webpack commands.