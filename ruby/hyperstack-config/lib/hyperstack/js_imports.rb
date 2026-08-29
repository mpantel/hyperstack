module Hyperstack
  class << self
    def js_import(value, client_only: nil, server_only: nil, defines:)
      defines = [*defines]
      if RUBY_ENGINE != 'opal'
        import(value, client_only: client_only, server_only: server_only, js_import: true)
      else
        on_server = `typeof Opal.global.document === 'undefined'`
        return if (server_only && !on_server) || (client_only && on_server)
        defines.each do |name|
          # NB: reference the `name` local directly in the backtick. Opal 1.8 does
          # NOT interpolate `#{name}` inside backticks, so `Opal.global['#{name}']`
          # compiled to the literal `Opal.global['name']` — which is masked in the
          # browser (window.name always exists) but ALWAYS raised under V8
          # prerendering (globalThis.name is undefined). That's why prerendering
          # was stuck off. See #19.
          next unless `Opal.global[name] === undefined`
          raise "The package #{name} was not found. Add it to the webpack "\
                "#{client_only ? 'client_only.js' : 'client_and_server.js'} manifest."
        end
      end
    end
  end
end
