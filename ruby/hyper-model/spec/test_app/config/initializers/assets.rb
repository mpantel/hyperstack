# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = '1.0'

# Add additional assets to the asset load path
# Rails.application.config.assets.paths << Emoji.images_path

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in app/assets folder are already added.
Rails.application.config.assets.precompile += %w[time_cop.js]

Opal::Config.source_map_enabled = true # default

# Asset modes:
#   * PRECOMPILED_ASSETS (parallel jobs): the bundle is precompiled once before
#     the workers start and served statically (compile=false), so there is no
#     runtime compilation to race. Turn debug off so the manifest is used.
#   * otherwise (normal single-process jobs): keep debug mode. Under parallel_tests
#     without precompile, give each process its own Sprockets cache dir as a
#     partial mitigation (TEST_ENV_NUMBER is only set by parallel_tests).
if ENV['PRECOMPILED_ASSETS']
  Rails.application.config.assets.debug = false
else
  Rails.application.config.assets.debug = true
  if ENV['TEST_ENV_NUMBER']
    Rails.application.config.assets.configure do |env|
      env.cache = Sprockets::Cache::FileStore.new(
        Rails.root.join("tmp/cache/assets/proc#{ENV['TEST_ENV_NUMBER']}").to_s
      )
    end
  end
end