require_relative 'install_generator_base'
module Hyperstack
  class  InstallBootstrapGenerator < Rails::Generators::Base

    desc "Adds the bits you need for the Bootstrap 3.0 framework"

    class_option 'no-build', type: :boolean

    # Pick the app's JS pipeline before anything else runs, exactly as
    # install_generator_base#install_webpack does. Thor runs public methods in
    # definition order, so every step below can rely on the strategy being mixed
    # in. Without this the generator hardcoded the Webpacker answer and silently
    # did nothing on an esbuild app: it appended to a pack manifest that esbuild
    # never reads, so `BS` was simply undefined at render time. (#98)
    def select_js_pipeline
      extend(js_pipeline_strategy)
    end

    # Each strategy words this for its own toolchain.
    def insure_node_loaded
      insure_yarn_loaded
    end

    def expose_bootstrap
      expose_npm_global 'BS', 'react-bootstrap'
    end

    # Bootstrap's CSS comes from a CDN on both pipelines, so this one step does
    # not go through the strategy.
    def add_style_sheet_link_tags
      inject_into_file 'app/views/layouts/application.html.erb', after: /stylesheet_link_tag.*$/ do
        <<-JAVASCRIPT

    <!-- Latest compiled and minified CSS -->
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css" integrity="sha384-BVYiiSIFeK1dGmJRAkycuHAHRg32OmUcww7on3RYdg4Va+PmSTsz/K68vbdEjh4u" crossorigin="anonymous">

    <!-- Optional theme -->
    <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap-theme.min.css" integrity="sha384-rHyoN1iRsVXV4nD0JutlnGaslCJuC7uwjduW9SVrLvRYooPp2bWYgmgJQIXwl/Sp" crossorigin="anonymous">
        JAVASCRIPT
      end
    end

    def install_packages
      yarn 'react-bootstrap'
      yarn 'bootstrap', '3'
    end

    def build_bundle
      build_js_bundle unless options['no-build']
    end

    def add_sample_component
      create_file 'app/hyperstack/components/bs_sampler.rb' do
        <<-RUBY
class BsSampler
  include Hyperstack::Component
  include Hyperstack::State::Observer
  render(DIV) do
    BS::Grid() do
      BS::Row(class: "show-grid") do
        BS::Col(xs: 12, md: 8) do
          CODE { "BS::Col(xs: 12, md: 8)" }
        end
        BS::Col(xs: 6, md: 4) do
          CODE { "BS::Col(xs: 6, md: 4)" }
        end
      end
      BS::Row() do
        BS::Alert(bsStyle: "warning") do
          STRONG { "Holy guacamole!" }
          SPAN { " Best check yo self, you're not looking too good." }
        end
      end
    end
  end
end
        RUBY
      end
    end
  end
end
