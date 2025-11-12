require 'spec_helper'

describe 'Hyperstack Webpack Bundle Control' do
  before(:each) do
    # Reset the setting to default
    Hyperstack.auto_import_webpack_bundles = true
  end

  describe 'auto_import_webpack_bundles setting' do
    it 'defaults to true for backward compatibility' do
      expect(Hyperstack.auto_import_webpack_bundles).to eq(true)
    end

    it 'can be set to false' do
      Hyperstack.auto_import_webpack_bundles = false
      expect(Hyperstack.auto_import_webpack_bundles).to eq(false)
    end

    it 'can be set to true' do
      Hyperstack.auto_import_webpack_bundles = true
      expect(Hyperstack.auto_import_webpack_bundles).to eq(true)
    end
  end

  describe 'handle_webpack' do
    let(:mock_manifest) do
      double('manifest')
    end

    before(:each) do
      # Mock Webpacker if not already defined
      unless defined?(Webpacker)
        stub_const('Webpacker', Class.new do
          def self.manifest
            # Will be mocked in each test
          end
        end)
      end

      # Setup manifest lookup to return appropriate values
      allow(mock_manifest).to receive(:lookup).with('client_only.js').and_return('/packs/client_only-abc123.js')
      allow(mock_manifest).to receive(:lookup).with('client_and_server.js').and_return('/packs/client_and_server-def456.js')
      allow(Webpacker).to receive(:manifest).and_return(mock_manifest)

      # Clear import list
      Hyperstack.instance_variable_set(:@import_list, [])
    end

    context 'when auto_import_webpack_bundles is true' do
      before(:each) do
        Hyperstack.auto_import_webpack_bundles = true
      end

      it 'imports webpack bundles into the import list' do
        # Trigger handle_webpack by calling generate_requires
        Hyperstack.send(:handle_webpack)

        import_list = Hyperstack.import_list

        # Should have imported both bundles
        bundle_names = import_list.map(&:first)
        expect(bundle_names).to include('client_only-abc123.js')
        expect(bundle_names).to include('client_and_server-def456.js')
      end
    end

    context 'when auto_import_webpack_bundles is false' do
      before(:each) do
        Hyperstack.auto_import_webpack_bundles = false
      end

      it 'does not import webpack bundles into the import list' do
        # Trigger handle_webpack
        Hyperstack.send(:handle_webpack)

        import_list = Hyperstack.import_list

        # Should not have imported any bundles
        bundle_names = import_list.map(&:first)
        expect(bundle_names).not_to include('client_only-abc123.js')
        expect(bundle_names).not_to include('client_and_server-def456.js')
      end

      it 'allows loading bundles via javascript_pack_tag in layouts' do
        # This is a configuration test - when disabled, the bundles
        # should be loaded manually in the layout, not embedded in Sprockets
        Hyperstack.send(:handle_webpack)

        # Verify no automatic import
        import_list = Hyperstack.import_list
        expect(import_list).to be_empty
      end
    end

    context 'when Webpacker is not defined' do
      before(:each) do
        hide_const('Webpacker')
      end

      it 'does not raise an error' do
        expect { Hyperstack.send(:handle_webpack) }.not_to raise_error
      end
    end

    context 'when manifest lookup fails' do
      before(:each) do
        allow(mock_manifest).to receive(:lookup).and_raise(StandardError, "Manifest not found")
      end

      it 'rescues the error and continues' do
        expect { Hyperstack.send(:handle_webpack) }.not_to raise_error
      end
    end
  end
end
