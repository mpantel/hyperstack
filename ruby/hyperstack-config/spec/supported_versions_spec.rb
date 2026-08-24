# Deliberately standalone: SupportedVersions is plain Ruby with no Rails
# dependency, so this spec does not load spec_helper (which boots a Rails
# test_app). That keeps it runnable on every line in the matrix, including ones
# whose test_app cannot boot.
require 'tmpdir'
require File.expand_path('../lib/hyperstack/supported_versions', __dir__)

describe Hyperstack::SupportedVersions do
  let(:table) do
    <<~YAML
      cells:
        - { id: low,  ruby: "3.4", rails: "6.1", opal: "1.8", react_rails: "2.6" }
        - { id: high, ruby: "4.0", rails: "8.1", opal: "1.8", react_rails: "3.3" }
    YAML
  end

  let(:path) { File.join(Dir.tmpdir, "supported_versions_spec_#{Process.pid}.yml") }

  before do
    File.write(path, table)
    described_class.reset!
    described_class.table_path = path
  end

  after do
    File.delete(path) if File.exist?(path)
    described_class.reset!
  end

  def combo(ruby: '3.4', rails: '6.1', opal: '1.8', react_rails: '2.6')
    { 'ruby' => ruby, 'rails' => rails, 'opal' => opal, 'react_rails' => react_rails }
  end

  it 'reports an exact cell as supported' do
    expect(described_class.status(combo)).to eq :supported
    expect(described_class.describe(combo)).to include "matches cell 'low'"
  end

  it 'reports a combination inside the spans but with no cell as untested' do
    # rails 7.2 sits between the 6.1 and 8.1 cells: plausible, but nothing runs it
    expect(described_class.status(combo(rails: '7.2', react_rails: '3.3'))).to eq :untested
    expect(described_class.describe(combo(rails: '7.2', react_rails: '3.3')))
      .to include 'not a tested combination'
  end

  it 'reports a combination outside the spans as unsupported' do
    expect(described_class.status(combo(ruby: '4.0', rails: '8.2', react_rails: '3.3')))
      .to eq :unsupported
  end

  it 'will not classify a partly detectable environment' do
    # loaded outside Rails: saying either "supported" or "unsupported" would be
    # a claim we cannot back up
    expect(described_class.status(combo(rails: nil))).to eq :unknown
    expect(described_class.describe(combo(rails: nil))).to include 'cannot check'
  end

  it 'is :unknown when no table can be found' do
    described_class.reset!
    described_class.table_path = File.join(Dir.tmpdir, 'definitely-not-here.yml')
    allow(described_class).to receive(:cells).and_return([])
    expect(described_class.status(combo)).to eq :unknown
  end

  describe '.check!' do
    it 'raises on an unsupported combination even in :warn mode' do
      allow(described_class).to receive(:status).and_return(:unsupported)
      expect { described_class.check!(mode: :warn) }.to raise_error(/NOT a supported configuration/)
    end

    it 'only warns on an untested combination in :warn mode' do
      allow(described_class).to receive(:status).and_return(:untested)
      expect(described_class).to receive(:warn).with(/not a tested combination/)
      expect { described_class.check!(mode: :warn) }.not_to raise_error
    end

    it 'raises on an untested combination in :raise mode' do
      allow(described_class).to receive(:status).and_return(:untested)
      expect { described_class.check!(mode: :raise) }.to raise_error(/not a tested combination/)
    end

    it 'reports at most once per process' do
      allow(described_class).to receive(:status).and_return(:untested)
      expect(described_class).to receive(:warn).once
      2.times { described_class.check!(mode: :warn) }
    end

    it 'says nothing for a supported combination' do
      allow(described_class).to receive(:status).and_return(:supported)
      expect(described_class).not_to receive(:warn)
      expect(described_class.check!).to eq :supported
    end
  end
end
