require 'spec_helper'

# Regression coverage for #108.
#
# react_runtime is its own sprockets asset now: application.js no longer
# concatenates it, so the harness page -- which has no layout, and never had one
# -- must emit its own include tag, ahead of the Opal bundle. window.React has to
# exist by the time Hyperstack boots, so the ORDER is the assertion, not a detail.
#
# The guard is what makes this safe to run everywhere. The same harness serves
# the react-rails/Webpacker cells, which have no react_runtime asset at all, and
# an unguarded javascript_include_tag there raises
# Sprockets::Rails::Helper::AssetNotFound on every page of every spec in every
# gem -- the whole matrix, from one line. The guard also has to answer in both
# asset modes, and they read from different places: live sprockets from the
# environment, precompiled from the manifest (PRECOMPILED_ASSETS sets
# config.assets.compile = false, which leaves Rails.application.assets nil).
#
# Driving the module directly keeps this a unit spec -- no app, no browser -- so
# every asset mode is covered without needing a cell for each.
describe HyperSpec::Internal::RailsControllerHelpers::Helpers do
  let(:harness) do
    Object.new.tap do |o|
      o.extend(described_class)
      o.instance_variable_set(:@page, [])
    end
  end

  def page
    harness.instance_variable_get(:@page).join("\n")
  end

  # A plain double responds only to what it is given, so omitting :assets_manifest
  # is how "this sprockets-rails has no manifest" is expressed.
  def stub_rails(manifest: nil, env: :none)
    stubs = {}
    stubs[:assets] = env unless env == :none
    app = double('Rails.application', **stubs)
    allow(app).to receive(:assets_manifest).and_return(manifest) if manifest
    allow(::Rails).to receive(:application).and_return(app)
  end

  def manifest_listing(*logical_paths)
    double('manifest', assets: logical_paths.to_h { |p| [p, "#{p.sub('.js', '')}-deadbeef.js"] })
  end

  def sprockets_env(resolving: [])
    double('sprockets').tap do |env|
      allow(env).to receive(:[]) { |path| resolving.include?(path) ? double('asset') : nil }
    end
  end

  describe '#react_runtime_asset?' do
    it 'is true from the manifest when assets are precompiled and the environment is gone' do
      stub_rails(manifest: manifest_listing('react_runtime.js', 'application.js'), env: nil)
      expect(harness.react_runtime_asset?).to be true
    end

    it 'is true from the sprockets environment when assets compile live' do
      stub_rails(manifest: manifest_listing, env: sprockets_env(resolving: %w[react_runtime]))
      expect(harness.react_runtime_asset?).to be true
    end

    # The react-rails / Webpacker cells: React is inside the application bundle,
    # there is no react_runtime asset, and asking for one must not raise.
    it 'is false when neither the manifest nor the environment has it' do
      stub_rails(manifest: manifest_listing('application.js'), env: sprockets_env)
      expect(harness.react_runtime_asset?).to be false
    end

    # The reason the environment is asked FIRST. These test_apps set
    # config.assets.debug, which drops :manifest from config.assets.resolve_with
    # entirely -- so a public/assets manifest left behind by an earlier
    # precompile lists an asset the include tag cannot actually resolve.
    # Trusting it there is AssetNotFound on every page, from a file nothing in
    # the current run wrote.
    it 'is false when only a stale manifest has it and the live environment does not' do
      stub_rails(manifest: manifest_listing('react_runtime.js'), env: sprockets_env)
      expect(harness.react_runtime_asset?).to be false
    end

    it 'is false when there is no manifest and no environment' do
      stub_rails(env: nil)
      expect(harness.react_runtime_asset?).to be false
    end

    # Reading the manifest touches the filesystem. A missing or unreadable one
    # must degrade to "no tag", never take the suite down.
    it 'is false rather than raising when the manifest cannot be read' do
      app = double('Rails.application', assets: nil)
      allow(app).to receive(:assets_manifest).and_raise(Errno::ENOENT)
      allow(::Rails).to receive(:application).and_return(app)
      expect(harness.react_runtime_asset?).to be false
    end
  end

  describe '#application!' do
    before do
      # opal_bootstrap! reaches into sprockets to decide whether the named asset
      # is Opal source; it is exercised by its own path and stubbed here so these
      # examples are about the tags.
      allow(harness).to receive(:opal_bootstrap!).and_return('')
    end

    it 'emits react_runtime before the application bundle when the asset exists' do
      stub_rails(manifest: manifest_listing('react_runtime.js'), env: nil)
      harness.application!('application')
      body = page
      expect(body).to include("javascript_include_tag 'react_runtime'")
      expect(body.index('react_runtime')).to be < body.index("javascript_include_tag 'application'")
    end

    it 'emits only the application bundle when there is no react_runtime asset' do
      stub_rails(manifest: manifest_listing('application.js'), env: sprockets_env)
      harness.application!('application')
      expect(page).not_to include('react_runtime')
      expect(page).to include("javascript_include_tag 'application'")
    end

    # #108 point 4: opal_bootstrap! branches on the named file (Opal source vs JS
    # manifest). Prepending a tag must not change which file it is asked about --
    # get that wrong and an Opal asset named by `client_option javascript:` is
    # registered and never executed, which surfaces as undefined methods deep in
    # the Opal runtime rather than as anything to do with this change.
    it 'still bootstraps the file it was given, not react_runtime' do
      stub_rails(manifest: manifest_listing('react_runtime.js'), env: nil)
      expect(harness).to receive(:opal_bootstrap!).with('factorial').and_return('')
      harness.application!('factorial')
    end

    it 'bootstraps the given file on the pipeline that has no react_runtime too' do
      stub_rails(manifest: manifest_listing, env: sprockets_env)
      expect(harness).to receive(:opal_bootstrap!).with('factorial').and_return('')
      harness.application!('factorial')
    end
  end
end
