# Legacy definition of HyperI18n
module HyperI18n
  class I18n
    extend HelperMethods
    include Hyperstack::Component::IsomorphicHelpers

    before_first_mount do
      if RUBY_ENGINE != 'opal'
        @server_data_cache = { t: {}, l: {} }
      else
        unless on_opal_server? || no_initial_data?
          I18nStore.translations = JSON.from_object(`window.HyperI18nInitialData.t`)
          I18nStore.localizations = JSON.from_object(`window.HyperI18nInitialData.l`)
        end
      end
    end

    isomorphic_method(:t) do |f, attribute, opts = {}|
      f.when_on_client do
        # NB: no `return` inside this block — under Opal 1.6+ a return from a
        # block invoked outside its defining method raises "unexpected return".
        if I18nStore.translations[attribute]
          I18nStore.translations[attribute]
        else
          Translate
            .run(attribute: attribute, opts: opts)
            .then do |translation|
              I18nStore.translations[attribute] = translation
              I18nStore.mutate.translations(I18nStore.translations)
            end

          opts[:default] || ''
        end
      end

      f.when_on_server do
        @server_data_cache[:t][attribute] = ::I18n.t(attribute, **opts.symbolize_keys)
      end
    end

    isomorphic_method(:l) do |f, date_or_time, format = :default, opts = {}|
      format = formatted_format(format)
      date_or_time = formatted_date_or_time(date_or_time)

      f.when_on_client do
        # NB: no `return` inside this block (see note on :t above).
        if I18nStore.localizations[date_or_time.to_s] &&
           I18nStore.localizations[date_or_time.to_s][format]
          I18nStore.localizations[date_or_time.to_s][format]
        else
          Localize
            .run(date_or_time: date_or_time, format: format, opts: {})
            .then do |localization|
              I18nStore.localizations[date_or_time.to_s] ||= {}
              I18nStore.localizations[date_or_time.to_s][format] = localization

              I18nStore.mutate.localizations(I18nStore.localizations)
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

# we now allow directly using I18n on client (as on server)
if RUBY_ENGINE == 'opal'
  module I18n
    class << self
      def t(*args)
        HyperI18n::I18n.t(*args)
      end
      def l(*args)
        HyperI18n::I18n.l(*args)
      end
    end
  end
end
