# Stream output live instead of dumping it when the process exits. Ruby's own IO
# buffering (not glibc's, so `stdbuf` has NO effect here) holds output until ~8KB
# or exit whenever stdout is not a tty -- true of every CI job, which is why a
# progressing run can look hung for minutes. (#69)
$stdout.sync = true
$stderr.sync = true

require 'pry'
require 'opal-browser'

ENV['RAILS_ENV'] ||= 'test'
require File.expand_path('../test_app/config/environment', __FILE__)

require 'rspec/rails'
require 'hyper-spec'
require 'hyper-i18n'
# require 'mini_racer'

RSpec.configure do |config|

  # config.before :suite do
  #   MiniRacer_Backup = MiniRacer
  #   Object.send(:remove_const, :MiniRacer)
  # end

  # config.around(:each, :prerendering_on) do |example|
  #   MiniRacer = MiniRacer_Backup
  #   example.run
  #   Object.send(:remove_const, :MiniRacer)
  # end

  config.color = true
  config.formatter = :documentation
  config.before(:all) do
    `rm -rf spec/test_app/tmp/cache/`
  end

  # Use legacy hyper-spec on_client behavior
  HyperSpec::Helpers.alias_method :on_client, :before_mount
end
