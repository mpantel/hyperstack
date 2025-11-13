require 'spec_helper'

describe 'Hyperstack::Internal::I18n unit tests' do
  before(:each) do
    # Setup translations
    I18n.backend.store_translations(:en, {
      test: {
        greeting: 'Hello',
        farewell: 'Goodbye',
        welcome: 'Welcome',
        greeting_with_name: 'Hello, %{name}!'
      },
      activerecord: {
        models: {
          test_model: 'Test Model'
        },
        attributes: {
          test_model: {
            name: 'Name',
            email: 'Email Address'
          }
        }
      }
    })
  end

  describe 'ActiveRecord integration' do
    before(:all) do
      # Create a test model class
      unless defined?(TestModel)
        class TestModel < ActiveRecord::Base
          self.table_name = 'users' # Use existing table from test_app
        end
      end
    end

    it 'translates model names via model_name.human' do
      expect(TestModel.model_name.human).to eq('Test Model')
    end

    it 'translates attribute names via human_attribute_name' do
      expect(TestModel.human_attribute_name('name')).to eq('Name')
      expect(TestModel.human_attribute_name('email')).to eq('Email Address')
    end

    it 'falls back to humanized attribute name if translation missing' do
      result = TestModel.human_attribute_name('nonexistent_field')
      expect(result).to eq('Nonexistent field')
    end
  end

  describe 'Hyperstack::I18n module' do
    it 'includes translations methods' do
      expect(Hyperstack::I18n).to be_a(Module)
    end

    it 'can be included in a class' do
      test_class = Class.new do
        include Hyperstack::I18n
      end

      expect(test_class.ancestors).to include(Hyperstack::I18n)
    end
  end

  describe 'Helper methods module' do
    it 'extends HelperMethods' do
      expect(Hyperstack::Internal::I18n.singleton_class.ancestors).to include(Hyperstack::Internal::I18n::HelperMethods)
    end

    it 'has formatted_format method' do
      expect(Hyperstack::Internal::I18n).to respond_to(:formatted_format)
    end

    it 'has formatted_date_or_time method' do
      expect(Hyperstack::Internal::I18n).to respond_to(:formatted_date_or_time)
    end
  end

  describe 'Server-side translation caching' do
    it 'uses ::I18n for translations' do
      # Test that standard I18n works
      expect(::I18n.t('test.greeting')).to eq('Hello')
      expect(::I18n.t('test.farewell')).to eq('Goodbye')
    end

    it 'handles interpolation' do
      result = ::I18n.t('test.greeting_with_name', name: 'World')
      expect(result).to eq('Hello, World!')
    end

    it 'handles missing keys' do
      result = ::I18n.t('test.nonexistent', default: 'Fallback')
      expect(result).to eq('Fallback')
    end

    it 'handles localization' do
      date = Time.parse('2025-01-15 14:30:00')
      result = ::I18n.l(date, format: '%Y-%m-%d')
      expect(result).to eq('2025-01-15')
    end
  end

  describe 'Promise class' do
    it 'is available' do
      expect(defined?(Promise)).to be_truthy
      expect(Promise).to be_a(Class)
    end

    it 'has value constructor' do
      expect(Promise).to respond_to(:value)
    end

    it 'has error constructor' do
      expect(Promise).to respond_to(:error)
    end

    it 'has when method for multiple promises' do
      expect(Promise).to respond_to(:when)
    end

    it 'can create a resolved promise' do
      promise = Promise.value('test')
      expect(promise).to be_a(Promise)
      expect(promise.value).to eq('test')
    end

    it 'can create a rejected promise' do
      promise = Promise.error('error')
      expect(promise).to be_a(Promise)
      expect(promise.error).to eq('error')
    end
  end

  describe 'Promise-based methods exist but are client-only' do
    it 'has t_async class method' do
      expect(Hyperstack::Internal::I18n).to respond_to(:t_async)
    end

    it 'has preload class method' do
      expect(Hyperstack::Internal::I18n).to respond_to(:preload)
    end

    it 't_async raises error on server due to Promise.resolve not existing' do
      # These methods are meant for Opal/client-side only
      # On server they try to call Promise.resolve which doesn't exist
      expect { Hyperstack::Internal::I18n.t_async('test.greeting') }.to raise_error(NoMethodError, /resolve/)
    end

    it 'preload raises error on server due to Promise.resolve not existing' do
      expect { Hyperstack::Internal::I18n.preload(['test.greeting']) }.to raise_error(NoMethodError, /resolve/)
    end
  end

  describe 'Store class' do
    it 'is only defined on client-side (Opal)' do
      # Store is defined with `if RUBY_ENGINE == 'opal'` guard
      # So it won't exist on server-side Ruby
      expect(RUBY_ENGINE).not_to eq('opal')
      expect(defined?(Hyperstack::Internal::I18n::Store)).to be_nil
    end
  end

  describe 'Operations' do
    it 'has Translate operation' do
      # Check that the operation class exists
      expect(defined?(Hyperstack::Internal::I18n::Translate)).to be_truthy
    end

    it 'has Localize operation' do
      expect(defined?(Hyperstack::Internal::I18n::Localize)).to be_truthy
    end

    it 'Translate inherits from Hyperstack::ServerOp' do
      expect(Hyperstack::Internal::I18n::Translate.ancestors).to include(Hyperstack::ServerOp)
    end

    it 'Localize inherits from Hyperstack::ServerOp' do
      expect(Hyperstack::Internal::I18n::Localize.ancestors).to include(Hyperstack::ServerOp)
    end

    describe 'Translate ServerOp locale handling' do
      before(:each) do
        # Setup translations in different locales
        I18n.backend.store_translations(:en, { locale_test: { key: 'English value' } })
        I18n.backend.store_translations(:el, { locale_test: { key: 'Greek value' } })
        I18n.backend.store_translations(:fr, { locale_test: { key: 'French value' } })

        # Configure available locales before setting default
        I18n.available_locales = [:en, :el, :fr]
        @original_default_locale = I18n.default_locale
      end

      after(:each) do
        I18n.default_locale = @original_default_locale
      end

      # The Translate ServerOp now extracts locale from acting_user.locale or session[:locale]
      # and uses I18n.with_locale() to ensure translations are fetched in the correct locale.
      #
      # For comprehensive end-to-end testing of this feature, see the integration tests
      # in the consuming application (e.g., invoicing/spec/components/base/i18n_inheritance_spec.rb)
      # which test real user authentication and session management.
      #
      # These unit tests verify the core I18n.with_locale mechanism that the ServerOp relies on.

      it 'I18n.with_locale correctly switches locale context' do
        I18n.default_locale = :el

        # Without with_locale, uses default
        expect(::I18n.t('locale_test.key')).to eq('Greek value')

        # With with_locale, uses specified locale
        ::I18n.with_locale(:en) do
          expect(::I18n.t('locale_test.key')).to eq('English value')
        end

        ::I18n.with_locale(:fr) do
          expect(::I18n.t('locale_test.key')).to eq('French value')
        end

        # After block, back to default
        expect(::I18n.t('locale_test.key')).to eq('Greek value')
      end

      it 'I18n.with_locale handles nested contexts correctly' do
        I18n.default_locale = :el

        ::I18n.with_locale(:en) do
          expect(::I18n.t('locale_test.key')).to eq('English value')

          # Nested locale context
          ::I18n.with_locale(:fr) do
            expect(::I18n.t('locale_test.key')).to eq('French value')
          end

          # Returns to outer context
          expect(::I18n.t('locale_test.key')).to eq('English value')
        end

        # Returns to default
        expect(::I18n.t('locale_test.key')).to eq('Greek value')
      end
    end
  end
end
