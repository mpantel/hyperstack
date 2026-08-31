module Hyperstack
  module Component
    module Server
      def self.render_to_string(element)
        if !(`typeof ReactDOMServer === 'undefined'`)
          Hyperstack::Internal::Component::RenderingContext.build { `ReactDOMServer.renderToString(#{element.to_n})` } # v0.15+
        else
          raise "renderToString is not defined. ReactDOMServer is not available in the browser. On the esbuild pipeline it is opt-in (#119): add `//= require react_dom_server_runtime` to app/assets/javascripts/application.js. On webpacker/sprockets, import ReactDOMServer yourself. Note server-side prerendering does NOT need this."
        end
      end

      def self.render_to_static_markup(element)
        if !(`typeof ReactDOMServer === 'undefined'`)
          Hyperstack::Internal::Component::RenderingContext.build { `ReactDOMServer.renderToStaticMarkup(#{element.to_n})` } # v0.15+
        else
          raise "renderToStaticMarkup is not defined. ReactDOMServer is not available in the browser. On the esbuild pipeline it is opt-in (#119): add `//= require react_dom_server_runtime` to app/assets/javascripts/application.js. On webpacker/sprockets, import ReactDOMServer yourself. Note server-side prerendering does NOT need this."
        end
      end
    end
  end
end
