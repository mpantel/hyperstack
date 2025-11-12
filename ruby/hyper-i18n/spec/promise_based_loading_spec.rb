require 'spec_helper'

describe 'Hyperstack::Internal::I18n Promise-Based Loading', js: true do
  # These specs test the promise-based translation loading methods
  # added to Hyperstack::Internal::I18n to eliminate race conditions

  before(:each) do
    # Setup test translations
    I18n.backend.store_translations(:en, {
      greeting: 'Hello',
      farewell: 'Goodbye',
      nested: {
        welcome: 'Welcome',
        thanks: 'Thank you'
      }
    })

    I18n.backend.store_translations(:es, {
      greeting: 'Hola',
      farewell: 'Adiós',
      nested: {
        welcome: 'Bienvenido',
        thanks: 'Gracias'
      }
    })
  end

  describe 'Hyperstack::Internal::I18n.t_async' do
    it 'returns a promise that resolves with the translation' do
      mount 'TestComponent' do
        class TestComponent < HyperComponent
          render(DIV) do
            DIV(id: 'status') { state.status }
            DIV(id: 'translation') { state.translation }

            if state.ready
              DIV(id: 'ready') { 'Ready' }
            end
          end

          before_mount do
            mutate.status 'Loading...'
            mutate.ready false

            Hyperstack::Internal::I18n.t_async('greeting').then do |translation|
              mutate.translation translation
              mutate.status 'Loaded'
              mutate.ready true
            end
          end
        end
      end

      # Initially shows loading
      expect(page).to have_selector('#status', text: 'Loading...')
      expect(page).to have_no_selector('#ready')

      # After promise resolves, shows translation
      expect(page).to have_selector('#translation', text: 'Hello', wait: 5)
      expect(page).to have_selector('#status', text: 'Loaded')
      expect(page).to have_selector('#ready', text: 'Ready')
    end

    it 'returns cached translation immediately if already loaded' do
      mount 'TestComponent' do
        class TestComponent < HyperComponent
          render(DIV) do
            DIV(id: 'first') { state.first_translation }
            DIV(id: 'second') { state.second_translation }
            DIV(id: 'status') { state.status }
          end

          before_mount do
            mutate.status 'Loading first...'

            # First call triggers async load
            Hyperstack::Internal::I18n.t_async('greeting').then do |trans1|
              mutate.first_translation trans1
              mutate.status 'Loading second...'

              # Second call for same key should use cache
              Hyperstack::Internal::I18n.t_async('greeting').then do |trans2|
                mutate.second_translation trans2
                mutate.status 'Both loaded'
              end
            end
          end
        end
      end

      expect(page).to have_selector('#first', text: 'Hello', wait: 5)
      expect(page).to have_selector('#second', text: 'Hello')
      expect(page).to have_selector('#status', text: 'Both loaded')
    end
  end

  describe 'Hyperstack::Internal::I18n.preload' do
    it 'preloads multiple translations and resolves when all are loaded' do
      mount 'TestComponent' do
        class TestComponent < HyperComponent
          render(DIV) do
            DIV(id: 'status') { state.status }

            if state.loaded
              DIV(id: 'greeting') { Hyperstack::Internal::I18n.t('greeting') }
              DIV(id: 'farewell') { Hyperstack::Internal::I18n.t('farewell') }
              DIV(id: 'welcome') { Hyperstack::Internal::I18n.t('nested.welcome') }
            end
          end

          before_mount do
            mutate.status 'Preloading...'
            mutate.loaded false

            keys = ['greeting', 'farewell', 'nested.welcome']
            Hyperstack::Internal::I18n.preload(keys).then do |translations|
              mutate.status "Loaded #{translations.size} translations"
              mutate.loaded true
            end
          end
        end
      end

      # Initially preloading
      expect(page).to have_selector('#status', text: 'Preloading...')

      # After preload completes
      expect(page).to have_selector('#status', text: 'Loaded 3 translations', wait: 5)
      expect(page).to have_selector('#greeting', text: 'Hello')
      expect(page).to have_selector('#farewell', text: 'Goodbye')
      expect(page).to have_selector('#welcome', text: 'Welcome')
    end

    it 'handles empty key array' do
      mount 'TestComponent' do
        class TestComponent < HyperComponent
          render(DIV) do
            DIV(id: 'status') { state.status }
          end

          before_mount do
            mutate.status 'Starting...'

            Hyperstack::Internal::I18n.preload([]).then do |translations|
              mutate.status "Empty array loaded: #{translations.inspect}"
            end
          end
        end
      end

      expect(page).to have_selector('#status', text: 'Empty array loaded: []', wait: 5)
    end

    it 'loads translations in parallel (not sequential)' do
      mount 'TestComponent' do
        class TestComponent < HyperComponent
          render(DIV) do
            DIV(id: 'status') { state.status }
            DIV(id: 'duration') { state.duration }
          end

          before_mount do
            mutate.status 'Loading...'
            start_time = Time.now

            # Preload 5 keys - should happen in parallel
            keys = ['greeting', 'farewell', 'nested.welcome', 'nested.thanks']
            Hyperstack::Internal::I18n.preload(keys).then do
              duration = ((Time.now - start_time) * 1000).to_i
              mutate.duration "#{duration}ms"
              mutate.status 'Complete'
            end
          end
        end
      end

      expect(page).to have_selector('#status', text: 'Complete', wait: 5)

      # Should complete in ~1 second, not 4+ seconds (would indicate sequential loading)
      duration_text = page.find('#duration').text
      duration_ms = duration_text.to_i
      expect(duration_ms).to be < 3000  # Allow generous timeout for CI
    end
  end

  describe 'Integration with component lifecycle' do
    it 'prevents flash of untranslated content by waiting for translations' do
      mount 'TestComponent' do
        class TestComponent < HyperComponent
          render(DIV) do
            if state.loading
              DIV(id: 'loading') { 'Loading translations...' }
            else
              DIV(id: 'content') do
                DIV(id: 'title') { Hyperstack::Internal::I18n.t('greeting') }
                DIV(id: 'subtitle') { Hyperstack::Internal::I18n.t('nested.welcome') }
              end
            end
          end

          before_mount do
            mutate.loading true

            Hyperstack::Internal::I18n.preload(['greeting', 'nested.welcome']).then do
              mutate.loading false
            end
          end
        end
      end

      # Should show loading state first
      expect(page).to have_selector('#loading', text: 'Loading translations...')

      # Then show translated content (no flash of keys)
      expect(page).to have_selector('#title', text: 'Hello', wait: 5)
      expect(page).to have_selector('#subtitle', text: 'Welcome')

      # Should never have shown the translation keys
      expect(page.html).not_to include('greeting')
      expect(page.html).not_to include('nested.welcome')
    end
  end

  describe 'Error handling' do
    it 'handles translation not found gracefully' do
      mount 'TestComponent' do
        class TestComponent < HyperComponent
          render(DIV) do
            DIV(id: 'status') { state.status }
            DIV(id: 'translation') { state.translation }
          end

          before_mount do
            mutate.status 'Loading...'

            Hyperstack::Internal::I18n.t_async('nonexistent.key', default: 'Fallback').then do |translation|
              mutate.translation translation
              mutate.status 'Loaded'
            end
          end
        end
      end

      expect(page).to have_selector('#translation', text: 'Fallback', wait: 5)
      expect(page).to have_selector('#status', text: 'Loaded')
    end
  end
end
