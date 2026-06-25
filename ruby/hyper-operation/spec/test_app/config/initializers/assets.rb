# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = '1.0'
Rails.application.config.assets.precompile += %w( time_cop.js )

# Add additional assets to the asset load path
# Rails.application.config.assets.paths << Emoji.images_path

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in app/assets folder are already added.
# Rails.application.config.assets.precompile += %w( search.js )

Opal::Config.source_map_enabled = true # default

# Asset modes. PRECOMPILED_ASSETS (parallel jobs): bundle is precompiled
# once and served statically (compile=false), so no runtime compilation races.
# Otherwise keep debug mode; under parallel_tests without precompile give each
# process its own Sprockets cache dir (TEST_ENV_NUMBER set only by parallel_tests).
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