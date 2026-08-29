# Stream output live instead of dumping it when the process exits. Ruby's own IO
# buffering (not glibc's, so `stdbuf` has NO effect here) holds output until ~8KB
# or exit whenever stdout is not a tty -- true of every CI job, which is why a
# progressing run can look hung for minutes. (#69)
$stdout.sync = true
$stderr.sync = true

require 'pry'
require 'opal-browser'
require 'database_cleaner'

ENV['RAILS_ENV'] ||= 'development'
require File.expand_path('../test_app/config/environment', __FILE__)

require 'rspec/rails'
require 'hyper-spec'
require 'rails-hyperstack'
require 'puma'
require 'turbolinks'

Capybara.server = :puma

RSpec.configure do |config|
  config.color = true
  config.formatter = :documentation
  config.before(:all) do
    `rm -rf spec/test_app/tmp/cache/`
  end
  config.before(:each, :js => true) do
    DatabaseCleaner.strategy = :truncation
    # Clean at the START of every attempt. RSpec::Retry re-runs before(:each) on
    # each retry, and the after-hook below skips cleaning on failure (to preserve
    # state for debugging) — so without this a flaked data-sync try leaves its
    # records behind and every retry starts dirty (`expected 0, got 1`), defeating
    # the retry. Cleaning up front makes each retry start clean and self-recover. (#20)
    DatabaseCleaner.clean
  end

  config.after(:each) do |example|
    unless example.exception
      # Clear session data
      Capybara.reset_sessions!
      # Rollback transaction
      DatabaseCleaner.clean
    end
  end
end
