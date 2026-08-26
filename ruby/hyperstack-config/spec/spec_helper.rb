# Stream output live instead of dumping it when the process exits. Ruby's own IO
# buffering (not glibc's, so `stdbuf` has NO effect here) holds output until ~8KB
# or exit whenever stdout is not a tty -- true of every CI job, which is why a
# progressing run can look hung for minutes. (#69)
$stdout.sync = true
$stderr.sync = true

require 'pry'

ENV['RAILS_ENV'] = 'test'
require File.expand_path('../test_app/config/environment', __FILE__)

require 'rspec/rails'
require 'timecop'
require 'hyperstack-config'

RSpec.configure do |config|
  config.color = true
  config.formatter = :documentation
end
