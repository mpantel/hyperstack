require 'spec_helper'
require 'hyperstack/hotloader/server'
require 'tmpdir'
require 'fileutils'
require 'json'

# These specs exercise the *server* half of the hot-reloader (the half that
# runs in the Rails process and pushes changes down the websocket). The client
# half lives in Opal (lib/hyperstack/hotloader.rb) and is covered by the browser
# specs. Here we drive Server#send_updated_file directly -- that is exactly what
# the Listen file-watcher callback calls for every modified/added/removed file --
# so the tests are deterministic and don't depend on filesystem-event timing.
describe Hyperstack::Hotloader::Server do
  # Records whatever the server would have pushed to a connected browser.
  class FakeClient
    attr_reader :sent
    def initialize
      @sent = []
    end

    def send(data)
      @sent << data
    end
  end

  # Grab a free TCP port so the server's TCPServer.new never collides with a
  # parallel test run.
  def free_port
    server = TCPServer.new('127.0.0.1', 0)
    port = server.addr[1]
    server.close
    port
  end

  around(:each) do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      Dir.chdir(dir) { example.run }
    end
  end

  def build_server(directories: [])
    @server = described_class.new(port: free_port, directories: directories)
  end

  # Inject a fake client and return what the server pushes for the given file.
  def updates_for(file)
    client = FakeClient.new
    @server.instance_variable_get(:@clients)[:fake] = client
    @server.send_updated_file(file)
    client.sent.map { |raw| JSON.parse(raw, symbolize_names: true) }
  end

  after(:each) do
    @server&.stop
  end

  describe '#setup_directories' do
    it 'auto-includes the known directories that exist on disk' do
      FileUtils.mkdir_p('app/views/components')
      FileUtils.mkdir_p('app/assets/stylesheets')
      build_server
      expect(@server.directories).to include('app/views/components')
      expect(@server.directories).to include('app/assets/stylesheets')
    end

    it 'does not include known directories that are absent' do
      build_server
      expect(@server.directories).not_to include('app/views/components')
    end

    it 'keeps any explicitly supplied directories' do
      build_server(directories: ['app/client'])
      expect(@server.directories).to include('app/client')
    end
  end

  describe '#send_updated_file' do
    before(:each) do
      FileUtils.mkdir_p('app/views/components')
      build_server
    end

    it 'pushes a ruby reload message for a changed .rb file' do
      path = File.join(@dir, 'app/views/components/foo.rb')
      File.write(path, "class Foo; end\n")

      update = updates_for(path).first

      expect(update[:type]).to eq('ruby')
      expect(update[:filename]).to eq(path)
      # the asset_path is the path with the watched-directory prefix stripped,
      # i.e. what the Opal client needs to locate the file in the asset tree.
      expect(update[:asset_path]).to eq('foo.rb')
      expect(update[:source_code]).to eq("class Foo; end\n")
    end

    it 'handles .rb.erb files as ruby reloads' do
      path = File.join(@dir, 'app/views/components/bar.rb.erb')
      File.write(path, "<%= 1 %>\n")

      update = updates_for(path).first

      expect(update[:type]).to eq('ruby')
      expect(update[:asset_path]).to eq('bar.rb.erb')
    end

    it 'pushes a css reload message for a changed stylesheet' do
      FileUtils.mkdir_p('app/assets/stylesheets')
      build_server
      path = File.join(@dir, 'app/assets/stylesheets/site.css')
      File.write(path, "body { color: red; }\n")

      update = updates_for(path).first

      expect(update[:type]).to eq('css')
      expect(update[:filename]).to eq(path)
      expect(update[:url]).to eq('app/assets/stylesheets/site.css')
    end

    it 'ignores files that are neither ruby nor stylesheets' do
      path = File.join(@dir, 'app/views/components/readme.txt')
      File.write(path, 'not reloadable')

      expect(updates_for(path)).to be_empty
    end

    it 'broadcasts the update to every connected client' do
      path = File.join(@dir, 'app/views/components/foo.rb')
      File.write(path, "class Foo; end\n")

      a = FakeClient.new
      b = FakeClient.new
      clients = @server.instance_variable_get(:@clients)
      clients[:a] = a
      clients[:b] = b

      @server.send_updated_file(path)

      expect(a.sent.length).to eq(1)
      expect(b.sent.length).to eq(1)
      expect(a.sent).to eq(b.sent)
    end
  end
end
