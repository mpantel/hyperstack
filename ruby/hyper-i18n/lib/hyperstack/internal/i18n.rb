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
          if translations_store[attribute]
            translations_store[attribute]
          else
            Translate
              .run(attribute: attribute, opts: opts)
              .then { |translation| cache_translation(attribute, translation) }

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
          if translations_store[attribute]
            # In Opal, use Promise.value() instead of Promise.resolve()
            Promise.value(translations_store[attribute])
          else
            # Return the promise from Translate operation
            Translate
              .run(attribute: attribute, opts: opts)
              .then do |translation|
                cache_translation(attribute, translation)
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
          if localizations_store[date_or_time.to_s] &&
             localizations_store[date_or_time.to_s][format]
            localizations_store[date_or_time.to_s][format]
          else
            Localize
              .run(date_or_time: date_or_time, format: format, opts: {})
              .then do |localization|
                cache_localization(date_or_time.to_s, format, localization)
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
        # Safe read access to the i18n stores. A preload/translation lookup can
        # run before the Store is initialized (e.g. a before_mount preload firing
        # before before_first_mount, or a non-default locale transient), which
        # raised "undefined method 'translations' for nil" on the client. Degrade
        # to an empty hash (= "no cached value") instead of raising. See #1.
        def translations_store
          Store.translations || {}
        rescue StandardError
          {}
        end

        def localizations_store
          Store.localizations || {}
        rescue StandardError
          {}
        end

        # Safe write access to the i18n stores. #1 guarded the *synchronous*
        # read path, but the .then callbacks in t/t_async/l fire after the
        # operation resolves — a guard at call time cannot protect a callback
        # that runs later, so an uninitialized Store raised the same
        # "undefined method 'translations' for nil", now inside a promise
        # chain where nothing catches it. Skip the cache update instead. See
        # #42 (follow-up to #1).
        def cache_translation(attribute, translation)
          return unless Store.translations

          Store.translations[attribute] = translation
          Store.mutate.translations(Store.translations)
        rescue StandardError
          nil
        end

        def cache_localization(key, format, localization)
          return unless Store.localizations

          Store.localizations[key] ||= {}
          Store.localizations[key][format] = localization
          Store.mutate.localizations(Store.localizations)
        rescue StandardError
          nil
        end

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
