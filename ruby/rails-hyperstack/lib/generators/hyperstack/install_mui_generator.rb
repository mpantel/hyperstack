require_relative 'install_generator_base'
module Hyperstack
  class  InstallMuiGenerator < Rails::Generators::Base

    desc "Adds the bits you need for the MUI framework"

    class_option 'no-build', type: :boolean

    # See InstallBootstrapGenerator for why this runs first. (#98)
    def select_js_pipeline
      extend(js_pipeline_strategy)
    end

    def insure_node_loaded
      insure_yarn_loaded
    end

    def expose_mui
      expose_npm_global 'Mui', 'muicss/react'
    end

    # MUI's CSS is the one place the two pipelines genuinely differ: Webpacker
    # compiles the package's scss from the pack, esbuild has no scss entrypoint
    # and takes the built CSS from the CDN. The strategy decides.
    def add_mui_stylesheet
      add_npm_stylesheet scss_path: 'muicss/lib/sass/mui',
                         cdn_url: 'https://cdn.muicss.com/mui-0.10.3/css/mui.min.css'
    end

    def install_packages
      yarn 'muicss'
    end

    def build_bundle
      build_js_bundle unless options['no-build']
    end

    def add_sample_component
      create_file 'app/hyperstack/components/mui_sampler.rb' do
        <<-RUBY
class MuiSampler
  include Hyperstack::Component
  include Hyperstack::State::Observer
  render(DIV) do
    Mui::Appbar()
    Mui::Container() do
      Mui::Button(color: :primary) { 'button' }
    end
  end
end
        RUBY
      end
    end
  end
end
