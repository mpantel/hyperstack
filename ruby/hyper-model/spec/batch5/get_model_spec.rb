require 'spec_helper'
require 'test_components'
require 'tmpdir'

describe "ReactiveRecord::ServerDataCache.get_model" do

  before(:each) do
    ActiveRecord::Base.public_columns_hash
  end

  it "will raise an access violation for an unknown class" do
    # A client string that names neither a known AR model nor a loaded constant
    # must be rejected. We can't assert on an app-resident-but-unloaded class
    # here: in this suite public_columns_hash require_dependency's app files, so
    # any autoloadable class ends up loaded (and is then legitimately allowed,
    # as the "already loaded" example below shows). Use a name that resolves to
    # no file and no model, so the guard rejects it in every environment. #22
    expect { ReactiveRecord::ServerDataCache.get_model('NoSuchHyperModel') }.to raise_error(Hyperstack::AccessViolation)
  end

  it "will not raise an access violation for an AR model in the Models folder" do
    expect(ReactiveRecord::ServerDataCache.get_model('Comment')).to eq Comment
  end

  it "will not raise an access violation if the class is already loaded" do
    expect(UnloadedClass).to eq ReactiveRecord::ServerDataCache.get_model('UnloadedClass')
  end

  # The gate above exists to stop a client-supplied string from autoloading an
  # arbitrary class. It was written as `const_defined?`, which cannot answer that
  # question under Zeitwerk -- every class under app/* has a registered autoload
  # at boot and so reports as "defined" before its file is ever loaded. The
  # examples from #22 cannot catch that: they can only reach classes this suite
  # has already loaded.
  #
  # So put the constant in exactly the state Zeitwerk leaves one in -- registered
  # with Ruby's own `autoload`, the mechanism Zeitwerk itself uses -- and the
  # assertions hold under either autoloader, on any Rails version. (#60)
  describe "a constant that is autoloadable but not yet loaded" do
    let!(:tmpdir) { Dir.mktmpdir('hyperstack-autoload-probe') }
    let(:probe_file) { File.join(tmpdir, 'hyperstack_zeitwerk_probe.rb') }

    before(:each) do
      $hyperstack_zeitwerk_probe_loaded = false
      File.write(
        probe_file,
        "$hyperstack_zeitwerk_probe_loaded = true\nclass HyperstackZeitwerkProbe; end\n"
      )
      Object.autoload(:HyperstackZeitwerkProbe, probe_file)
    end

    after(:each) do
      begin
        Object.send(:remove_const, :HyperstackZeitwerkProbe)
      rescue NameError
        nil
      end
      $hyperstack_zeitwerk_probe_loaded = nil
      FileUtils.remove_entry(tmpdir)
    end

    it "is reported as defined, which is why const_defined? cannot be the gate" do
      expect(Object.const_defined?('HyperstackZeitwerkProbe')).to be_truthy
      expect($hyperstack_zeitwerk_probe_loaded).to be false
    end

    it "is not reported as loaded" do
      expect(ReactiveRecord::ServerDataCache.constant_loaded?('HyperstackZeitwerkProbe')).to be_falsey
      # asking the question must not itself resolve the autoload
      expect($hyperstack_zeitwerk_probe_loaded).to be false
    end

    it "is refused, and is not autoloaded, when it is not a public model" do
      expect { ReactiveRecord::ServerDataCache.get_model('HyperstackZeitwerkProbe') }
        .to raise_error(Hyperstack::AccessViolation)
      expect($hyperstack_zeitwerk_probe_loaded).to be false
    end

    it "is not a key of public_columns_hash -- a pending autoload is not a public model" do
      expect(ActiveRecord::Base.public_columns_hash.key?('HyperstackZeitwerkProbe')).to be_falsey
      expect($hyperstack_zeitwerk_probe_loaded).to be false
    end
  end

  # The other half of the same fix: refusing unloaded constants must not refuse a
  # legitimately public model that simply has not been loaded yet. Under lazy
  # loading that is the normal state of every model until first use, so the gate
  # has to fall through to public_columns_hash and let it resolve the name. (#60)
  it "resolves a public model that is not loaded yet" do
    allow(ReactiveRecord::ServerDataCache).to receive(:constant_loaded?).and_call_original
    allow(ReactiveRecord::ServerDataCache).to receive(:constant_loaded?).with('Comment').and_return(false)
    expect(ReactiveRecord::ServerDataCache.get_model('Comment')).to eq Comment
  end
end
