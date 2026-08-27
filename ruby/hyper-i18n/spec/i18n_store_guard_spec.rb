require 'spec_helper'

# Issue #1: t/t_async/preload/l read the i18n Store before it is guaranteed
# initialized (and Store is client-only), which raised "undefined method
# 'translations' for nil" / uninitialized-constant on the client. The
# translations_store / localizations_store helpers degrade to {} instead of
# raising. Server-side the Store constant is absent, so these calls naturally
# exercise the guard.
describe Hyperstack::Internal::I18n do
  describe '.translations_store / .localizations_store (issue #1 guard)' do
    it 'never raises and always returns a Hash, even when the Store is unavailable' do
      expect { described_class.translations_store }.not_to raise_error
      expect { described_class.localizations_store }.not_to raise_error
      expect(described_class.translations_store).to be_a(Hash)
      expect(described_class.localizations_store).to be_a(Hash)
    end
  end

  # Issue #42: #1 only covered the synchronous read path. The .then callbacks
  # in t/t_async/l run after the Translate/Localize operation resolves, so the
  # sync guard at call time cannot protect them -- an uninitialized Store threw
  # the same error from inside the promise chain, where nothing catches it.
  describe '.cache_translation / .cache_localization (issue #42 guard)' do
    it 'never raises when the Store is unavailable' do
      expect { described_class.cache_translation('some.key', 'translated') }
        .not_to raise_error
      expect { described_class.cache_localization('2026-08-27', :default, 'localized') }
        .not_to raise_error
    end

    it 'writes through to the Store when it is initialized' do
      mutate = double('mutate')
      store = double('Store', translations: {}, localizations: {}, mutate: mutate)
      allow(mutate).to receive(:translations)
      allow(mutate).to receive(:localizations)
      stub_const('Hyperstack::Internal::I18n::Store', store)

      described_class.cache_translation('some.key', 'translated')
      expect(store.translations['some.key']).to eq('translated')
      expect(mutate).to have_received(:translations).with(store.translations)

      described_class.cache_localization('2026-08-27', :default, 'localized')
      expect(store.localizations['2026-08-27']).to eq(default: 'localized')
      expect(mutate).to have_received(:localizations).with(store.localizations)
    end

    it 'skips the write (rather than raising) when the Store is not initialized' do
      mutate = double('mutate')
      store = double('Store', translations: nil, localizations: nil, mutate: mutate)
      allow(mutate).to receive(:translations)
      allow(mutate).to receive(:localizations)
      stub_const('Hyperstack::Internal::I18n::Store', store)

      expect { described_class.cache_translation('some.key', 'translated') }
        .not_to raise_error
      expect { described_class.cache_localization('2026-08-27', :default, 'localized') }
        .not_to raise_error
      expect(mutate).not_to have_received(:translations)
      expect(mutate).not_to have_received(:localizations)
    end
  end
end
