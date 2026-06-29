require 'spec_helper'
require 'hyperstack/hotloader/server'
require 'timeout'
require 'fileutils'

# Browser-level proof of the client half of hot reloading: importing
# 'hyperstack/hotloader' (done in the test_app initializer, exactly as the
# installer does for development) must make the client connect to the hot-loader
# server on boot and evaluate files pushed down the websocket -- without any
# manual `Hyperstack::Hotloader.listen` call.
#
# A real Hyperstack::Hotloader::Server is run in a background thread; we drive
# send_updated_file directly (no Listen file-watching) so the test is
# deterministic. Runs against the remote Chrome container -- see
# run-local-docker-specs.sh.
describe 'Hyperstack hot reloading (client)', js: true do
  # the test_app leaves hotloader_port at its 25222 default, so that is the port
  # the client computes from the emitted JS config and connects to.
  let(:port) { 25222 }
  # the watched dir must be relative to Dir.pwd so the server can derive an
  # asset_path for pushed files (a nil asset_path would break the client reload).
  let(:watch_dir) { 'tmp/hotloader_spec' }

  def server_clients
    @server.instance_variable_get(:@clients)
  end

  def wait_until(timeout: 15)
    Timeout.timeout(timeout) { sleep 0.1 until yield }
  end

  before(:each) do
    FileUtils.mkdir_p(watch_dir)
    @server = Hyperstack::Hotloader::Server.new(port: port, directories: [watch_dir])
    @stop = false
    @thread = Thread.new do
      until @stop
        begin
          @server.run(0.1)
        rescue => e
          warn "hotloader test server: #{e.class}: #{e.message}"
        end
        sleep 0.02
      end
    end
  end

  after(:each) do
    @stop = true
    @thread&.join(2)
    @server&.stop
    FileUtils.rm_rf(watch_dir)
  end

  it 'connects to the hot-loader server automatically when the page loads' do
    visit '/'
    wait_until { server_clients.any? }
    expect(server_clients.size).to be >= 1
  end

  it 'evaluates ruby pushed from the server in the running page' do
    visit '/'
    wait_until { server_clients.any? }

    # push a file whose (ruby) source sets a JS global we can read back
    path = File.join(Dir.pwd, watch_dir, 'reloaded.rb')
    File.write(path, '`window.__hot_reloaded = 4242`')
    @server.send_updated_file(path)

    wait_until { evaluate_script('window.__hot_reloaded') == 4242 }
    expect(evaluate_script('window.__hot_reloaded')).to eq(4242)
  end
end
