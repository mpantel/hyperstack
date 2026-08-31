require 'hyper-spec'

class HyperSpecTestController < SimpleDelegator
  include HyperSpec::ControllerHelpers

  class << self
    attr_reader :sprocket_server
    attr_reader :asset_path

    def wrap(app:, append_path: 'app', asset_path: '/assets')
      @sprocket_server = Opal::Sprockets::Server.new do |s|
        s.append_path append_path
      end

      @asset_path = asset_path

      ::Rack::Builder.app(app) do
        map "/#{HyperSpecTestController.route_root}" do
          use HyperSpecTestController
        end
      end
    end
  end

  def sprocket_server
    self.class.sprocket_server
  end

  def asset_path
    self.class.asset_path
  end

  def ping!
    [204, {}, []]
  end

  # No react_runtime tag here, unlike the Rails harness (#108).
  #
  # This harness serves a Rack/Sinatra app from its own Opal::Sprockets::Server
  # rooted at `app`. There is no Rails asset pipeline behind it, no
  # `app/assets/builds`, and nothing that runs esbuild -- so react_runtime is not
  # an asset it could resolve, in any configuration. The split that made the
  # Rails harness emit a second tag has no counterpart to emit here.
  #
  # Recorded rather than left implicit because the two harnesses are easy to
  # assume identical: if a Rack app ever gains the esbuild pipeline, this is the
  # method that has to grow the same guarded tag.
  def application!(file)
    @page << Opal::Sprockets.javascript_include_tag(
      file,
      debug: true,
      sprockets: sprocket_server.sprockets,
      prefix: asset_path
    )
  end

  def json!
    @page << Opal::Sprockets.javascript_include_tag(
      'json',
      debug: true,
      sprockets: sprocket_server.sprockets,
      prefix: asset_path
    )
  end


  def style_sheet!(_file_); end

  def deliver!
    [200, { 'Content-Type' => 'text/html' }, [@page]]
  end

  def call(env)
    __setobj__(Rack::Request.new(env))
    params[:id] = path.split('/').last
    test
  end
end
