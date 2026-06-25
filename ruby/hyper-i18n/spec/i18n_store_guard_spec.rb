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
end
