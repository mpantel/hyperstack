module Hyperstack
  module Internal
    class I18n
      class Translate < Hyperstack::ServerOp
        param :acting_user, nils: true
        param :attribute
        param :opts
        param :translation, default: nil

        def opts
          params.opts.symbolize_keys
        end

        step do
          # Extract locale from acting_user or session to ensure translations
          # are fetched in the correct user locale, not the default locale.
          # Priority:
          # 1. acting_user.locale (most reliable when user is logged in)
          # 2. session[:locale] (fallback for guest users or when acting_user is nil)
          # 3. opts[:locale] (if explicitly passed)
          # 4. I18n.default_locale (last resort)

          user_locale = params.acting_user&.locale
          session_locale = respond_to?(:session) ? session[:locale] : nil
          target_locale = user_locale || session_locale || opts[:locale] || ::I18n.default_locale

          # Fetch translation in the correct locale context
          if target_locale && target_locale.to_s != ::I18n.default_locale.to_s
            ::I18n.with_locale(target_locale) do
              Rails.logger.debug "Translate ServerOp: attribute=#{params.attribute}, locale=#{target_locale} (from #{user_locale ? 'acting_user' : session_locale ? 'session' : 'opts/default'})"
              params.translation = ::I18n.t(params.attribute, **opts)
            end
          else
            Rails.logger.debug "Translate ServerOp: attribute=#{params.attribute}, locale=#{target_locale} (default)"
            params.translation = ::I18n.t(params.attribute, **opts)
          end
        end
      end
    end
  end
end
