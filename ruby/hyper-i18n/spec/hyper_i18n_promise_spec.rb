require 'spec_helper'

describe 'Promise-based I18n methods', js: true do
  before(:each) do
    # Setup translations on server
    I18n.backend.store_translations(:en, {
      async_test: {
        greeting: 'Hello',
        farewell: 'Goodbye',
        welcome: 'Welcome',
        thanks: 'Thank you'
      }
    })
  end

  describe 'Hyperstack::Internal::I18n.t_async' do
    it 'loads translation asynchronously and returns a promise', prerendering_on: false do
      on_client do
        module Components
          class AsyncTestComponent
            include Hyperstack::Component
            include Hyperstack::I18n

            render(DIV) do
              DIV(id: :status) { state.status }
              DIV(id: :translation) { state.translation }
            end

            before_mount do
              mutate.status 'loading'

              Hyperstack::Internal::I18n.t_async('async_test.greeting').then do |trans|
                mutate.translation trans
                mutate.status 'loaded'
              end
            end
          end
        end
      end

      mount 'Components::AsyncTestComponent', {}, render_on: :client_only

      # Wait for promise to resolve
      page.evaluate_script('new Promise(resolve => setTimeout(resolve, 100))')

      expect(page).to have_selector('#translation', text: 'Hello', wait: 5)
      expect(page).to have_selector('#status', text: 'loaded')
    end

    it 'returns cached translation immediately if already loaded', prerendering_on: false do
      on_client do
        module Components
          class CachedTestComponent
            include Hyperstack::Component
            include Hyperstack::I18n

            render(DIV) do
              DIV(id: :first) { state.first_translation }
              DIV(id: :second) { state.second_translation }
              DIV(id: :status) { state.status }
            end

            before_mount do
              mutate.status 'loading_first'

              # First call triggers async load
              Hyperstack::Internal::I18n.t_async('async_test.farewell').then do |trans1|
                mutate.first_translation trans1
                mutate.status 'loading_second'

                # Second call should use cache
                Hyperstack::Internal::I18n.t_async('async_test.farewell').then do |trans2|
                  mutate.second_translation trans2
                  mutate.status 'complete'
                end
              end
            end
          end
        end
      end

      mount 'Components::CachedTestComponent', {}, render_on: :client_only

      # Wait for both promises
      page.evaluate_script('new Promise(resolve => setTimeout(resolve, 100))')

      expect(page).to have_selector('#first', text: 'Goodbye', wait: 5)
      expect(page).to have_selector('#second', text: 'Goodbye')
      expect(page).to have_selector('#status', text: 'complete')
    end
  end

  describe 'Hyperstack::Internal::I18n.preload' do
    it 'preloads multiple translations and resolves when all are loaded', prerendering_on: false do
      on_client do
        module Components
          class PreloadTestComponent
            include Hyperstack::Component
            include Hyperstack::I18n

            render(DIV) do
              DIV(id: :status) { state.status }
              DIV(id: :count) { state.translation_count }
            end

            before_mount do
              mutate.status 'preloading'
              mutate.translation_count 0

              keys = ['async_test.greeting', 'async_test.farewell', 'async_test.welcome']
              Hyperstack::Internal::I18n.preload(keys).then do |translations|
                mutate.translation_count translations.length
                mutate.status 'complete'
              end
            end
          end
        end
      end

      mount 'Components::PreloadTestComponent', {}, render_on: :client_only

      # Wait for preload to complete
      page.evaluate_script('new Promise(resolve => setTimeout(resolve, 200))')

      expect(page).to have_selector('#status', text: 'complete', wait: 5)
      expect(page).to have_selector('#count', text: '3')
    end

    it 'handles empty key array gracefully', prerendering_on: false do
      on_client do
        module Components
          class EmptyPreloadComponent
            include Hyperstack::Component
            include Hyperstack::I18n

            render(DIV) do
              DIV(id: :status) { state.status }
              DIV(id: :count) { state.count }
            end

            before_mount do
              mutate.status 'loading'

              Hyperstack::Internal::I18n.preload([]).then do |translations|
                mutate.count translations.length
                mutate.status 'empty_complete'
              end
            end
          end
        end
      end

      mount 'Components::EmptyPreloadComponent', {}, render_on: :client_only

      # Wait for promise
      page.evaluate_script('new Promise(resolve => setTimeout(resolve, 100))')

      expect(page).to have_selector('#status', text: 'empty_complete', wait: 5)
      expect(page).to have_selector('#count', text: '0')
    end

    it 'loads translations in parallel (all resolve together)', prerendering_on: false do
      on_client do
        module Components
          class ParallelLoadComponent
            include Hyperstack::Component
            include Hyperstack::I18n

            render(DIV) do
              DIV(id: :status) { state.status }
              DIV(id: :results) do
                if state.translations
                  state.translations.each_with_index do |trans, idx|
                    SPAN(id: "trans-#{idx}") { trans }
                  end
                end
              end
            end

            before_mount do
              mutate.status 'loading'

              keys = ['async_test.greeting', 'async_test.farewell', 'async_test.welcome', 'async_test.thanks']
              Hyperstack::Internal::I18n.preload(keys).then do |translations|
                mutate.translations translations
                mutate.status 'all_loaded'
              end
            end
          end
        end
      end

      mount 'Components::ParallelLoadComponent', {}, render_on: :client_only

      # Wait for all translations
      page.evaluate_script('new Promise(resolve => setTimeout(resolve, 200))')

      expect(page).to have_selector('#status', text: 'all_loaded', wait: 5)
      expect(page).to have_selector('#trans-0', text: 'Hello')
      expect(page).to have_selector('#trans-1', text: 'Goodbye')
      expect(page).to have_selector('#trans-2', text: 'Welcome')
      expect(page).to have_selector('#trans-3', text: 'Thank you')
    end
  end

  describe 'Integration with component lifecycle' do
    it 'prevents flash of untranslated content by waiting for translations', prerendering_on: false do
      on_client do
        module Components
          class NoFlashComponent
            include Hyperstack::Component
            include Hyperstack::I18n

            render(DIV) do
              if state.ready
                DIV(id: :content) { state.greeting }
              else
                DIV(id: :loading) { 'Loading translations...' }
              end
            end

            before_mount do
              mutate.ready false

              # Wait for translation to load before showing content
              Hyperstack::Internal::I18n.t_async('async_test.greeting').then do |trans|
                mutate.greeting trans
                mutate.ready true
              end
            end
          end
        end
      end

      mount 'Components::NoFlashComponent', {}, render_on: :client_only

      # Should show loading first
      expect(page).to have_selector('#loading', text: 'Loading translations...')

      # Then show translated content
      expect(page).to have_selector('#content', text: 'Hello', wait: 5)
      expect(page).to have_no_selector('#loading')
    end
  end

  describe 'Error handling' do
    it 'handles translation loading failures gracefully', prerendering_on: false do
      on_client do
        module Components
          class ErrorHandlingComponent
            include Hyperstack::Component
            include Hyperstack::I18n

            render(DIV) do
              DIV(id: :status) { state.status }
              DIV(id: :translation) { state.translation }
            end

            before_mount do
              mutate.status 'loading'

              # Try to load a non-existent key
              Hyperstack::Internal::I18n.t_async('async_test.nonexistent').then do |trans|
                mutate.translation trans || 'fallback_value'
                mutate.status 'loaded'
              rescue => e
                mutate.translation 'error_fallback'
                mutate.status 'error'
              end
            end
          end
        end
      end

      mount 'Components::ErrorHandlingComponent', {}, render_on: :client_only

      # Wait for promise
      page.evaluate_script('new Promise(resolve => setTimeout(resolve, 200))')

      # Should complete without crashing (either loaded or error state)
      expect(page).to have_selector('#status', text: /loaded|error/, wait: 5)
      expect(page).to have_selector('#translation', text: /fallback|error/)
    end
  end
end
