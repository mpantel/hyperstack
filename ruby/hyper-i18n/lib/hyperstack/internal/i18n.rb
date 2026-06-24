module Hyperstack
  module Internal
    class I18n
      extend HelperMethods
      include Hyperstack::Component::IsomorphicHelpers

      before_first_mount do
        if RUBY_ENGINE != 'opal'
          @server_data_cache = { t: {}, l: {} }
        else
          unless on_opal_server? || no_initial_data?
            Store.translations = JSON.from_object(`window.HyperI18nInitialData.t`)
            Store.localizations = JSON.from_object(`window.HyperI18nInitialData.l`)
          end
        end
      end

      isomorphic_method(:t) do |f, attribute, opts = {}|
        f.when_on_client do
          # NB: no `return` inside this block — under Opal 1.6+ a return from a
          # block invoked outside its defining method raises "unexpected return".
          if Store.translations[attribute]
            Store.translations[attribute]
          else
            Translate
              .run(attribute: attribute, opts: opts)
              .then do |translation|
                Store.translations[attribute] = translation
                Store.mutate.translations(Store.translations)
              end

            opts[:default] || ''
          end
        end

        f.when_on_server do
          @server_data_cache[:t][attribute] = ::I18n.t(attribute, **opts.symbolize_keys)
        end
      end

      # Promise-based translation loading for preloading scenarios
      # Returns a promise that resolves when the translation is loaded
      # Usage:
      #   Hyperstack::Internal::I18n.t_async('key').then { |translation| puts translation }
      def self.t_async(attribute, opts = {})
        if RUBY_ENGINE == 'opal'
          # If already cached, return resolved promise
          if Store.translations[attribute]
            # In Opal, use Promise.value() instead of Promise.resolve()
            Promise.value(Store.translations[attribute])
          else
            # Return the promise from Translate operation
            Translate
              .run(attribute: attribute, opts: opts)
              .then do |translation|
                Store.translations[attribute] = translation
                Store.mutate.translations(Store.translations)
                translation
              end
          end
        else
          # On server, return synchronous value wrapped in resolved promise
          Promise.new.tap { |p| p.resolve(::I18n.t(attribute, **opts.symbolize_keys)) }
        end
      end

      # Preload multiple translations and return promise that resolves when all are loaded
      # Usage:
      #   Hyperstack::Internal::I18n.preload(['key1', 'key2']).then { puts "All loaded!" }
      def self.preload(keys, opts = {})
        if RUBY_ENGINE == 'opal'
          return Promise.value([]) if keys.blank?

          promises = keys.map { |key| t_async(key, opts) }
          Promise.when(*promises)
        else
          # On server, return resolved promise immediately
          result = keys.blank? ? [] : keys.map { |key| ::I18n.t(key, **opts.symbolize_keys) }
          Promise.new.tap { |p| p.resolve(result) }
        end
      end

      isomorphic_method(:l) do |f, date_or_time, format = :default, opts = {}|
        format = formatted_format(format)
        date_or_time = formatted_date_or_time(date_or_time)

        f.when_on_client do
          # NB: no `return` inside this block (see note on :t above).
          if Store.localizations[date_or_time.to_s] &&
             Store.localizations[date_or_time.to_s][format]
            Store.localizations[date_or_time.to_s][format]
          else
            Localize
              .run(date_or_time: date_or_time, format: format, opts: {})
              .then do |localization|
                Store.localizations[date_or_time.to_s] ||= {}
                Store.localizations[date_or_time.to_s][format] = localization

                Store.mutate.localizations(Store.localizations)
              end

            opts[:default] || ''
          end
        end

        f.when_on_server do
          @server_data_cache[:l][date_or_time.to_s] ||= {}

          @server_data_cache[:l][date_or_time.to_s][format] =
            ::I18n.l(date_or_time, **opts.with_indifferent_access.merge(format: format).symbolize_keys)
        end
      end

      if RUBY_ENGINE != 'opal'
        prerender_footer do
          "<script type=\"text/javascript\">\n"\
            "if (typeof window.HyperI18nInitialData === 'undefined') {\n"\
            "  window.HyperI18nInitialData = #{initial_data_json};\n"\
            "}\n"\
            "</script>\n"
        end
      end

      class << self
        def no_initial_data?
          `typeof window.HyperI18nInitialData === 'undefined'`
        end

        def initial_data_json
          if @server_data_cache
            @server_data_cache.as_json.to_json
          else
            { t: {}, l: {} }.to_json
          end
        end
      end
    end
  end
end

# we now allow directly using I18n on client (as on server)
