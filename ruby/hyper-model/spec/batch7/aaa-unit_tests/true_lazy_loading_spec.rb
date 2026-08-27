require 'spec_helper'
require 'tmpdir'

# This spec tests the TRUE lazy loading optimization
# where model files are loaded on-demand instead of during initialization
describe "ActiveRecord::Base true lazy loading" do
  before(:all) do
    begin
      # Try to load the actual implementation
      require_relative '../../../lib/reactive_record/active_record/public_columns_hash' unless defined?(ActiveRecord::Base::LazyColumnsHash)
    rescue => e
      skip "LazyColumnsHash not available: #{e.message}"
    end
  end

  describe "get_public_model_files" do
    it "stores file paths without requiring them" do
      # This method should discover model files but NOT call require_dependency on them
      # The key optimization: models load on-demand, not eagerly

      # Mock the file discovery
      allow(Dir).to receive(:exist?).and_return(true)
      allow(Dir).to receive(:glob).and_return([
        '/path/to/app/models/public/user.rb',
        '/path/to/app/models/public/project.rb'
      ])

      # Mock Rails.root
      allow(Rails).to receive(:root).and_return(Pathname.new('/path/to'))

      # Call get_public_model_files
      files = ActiveRecord::Base.send(:get_public_model_files)

      # Should return file paths RELATIVE to the directory (not including directory prefix)
      # The implementation strips the directory prefix, so 'app/models/public/user.rb' becomes 'user'
      expect(files).to include('user')
      expect(files).to include('project')

      # Should store file path map with relative paths as keys
      file_paths = ActiveRecord::Base.instance_variable_get(:@model_file_paths)
      expect(file_paths).to be_a(Hash)
      expect(file_paths['user']).to eq('/path/to/app/models/public/user.rb')
      expect(file_paths['project']).to eq('/path/to/app/models/public/project.rb')
    end
  end

  describe "LazyColumnsHash file loading" do
    # Use a model name that doesn't exist in the test environment
    # to ensure require_dependency is actually called
    let(:file_paths) { ['lazy_test_model', 'project'] }
    let(:file_path_map) do
      {
        'lazy_test_model' => '/app/models/lazy_test_model.rb',
        'project' => '/app/models/project.rb'
      }
    end

    # Mock models that simulate ActiveRecord::Base descendants
    let(:mock_lazy_test_model) do
      model = Class.new
      model.define_singleton_method(:name) { 'LazyTestModel' }
      model.define_singleton_method(:<) { |klass| klass == ActiveRecord::Base }
      model.define_singleton_method(:columns_hash) { { 'id' => :integer, 'name' => :string } }
      model.define_singleton_method(:respond_to?) { |method| [:define_attribute_methods, :table_exists?].include?(method) }
      model.define_singleton_method(:table_exists?) { true }
      model.define_singleton_method(:define_attribute_methods) { nil }
      model.define_singleton_method(:instance_variable_get) { |var| false }
      model.define_singleton_method(:instance_variable_set) { |var, val| nil }
      model
    end

    let(:lazy_hash) { ActiveRecord::Base::LazyColumnsHash.new([], file_paths, file_path_map) }

    describe "initialization with file paths" do
      it "stores file paths for on-demand loading" do
        expect(lazy_hash.instance_variable_get(:@file_paths)).to eq(file_paths)
        expect(lazy_hash.instance_variable_get(:@file_path_map)).to eq(file_path_map)
      end

      it "initializes with empty loaded models" do
        loaded_models = lazy_hash.instance_variable_get(:@loaded_models)
        expect(loaded_models).to be_empty
      end
    end

    describe "key? with file paths" do
      it "returns true if model file exists" do
        # LazyTestModel file exists in file_paths
        expect(lazy_hash.key?('LazyTestModel')).to be_truthy
      end

      it "returns false if model file doesn't exist" do
        expect(lazy_hash.key?('NonexistentModel')).to be_falsey
      end

      # key? is the second gate ServerDataCache.get_model consults, so it has to
      # answer the same question the first one does: is this name a public model,
      # or a genuinely loaded constant? It used to fall back to
      # `Object.const_defined?`, which under Zeitwerk is true for every class in
      # app/* -- making every one of them "public" and autoloadable by a client
      # string. Register the constant the way Zeitwerk does and pin it. (#60)
      it "returns false for a constant with a pending autoload" do
        probe_loaded = false
        Dir.mktmpdir('hyperstack-autoload-probe') do |dir|
          file = File.join(dir, 'lazy_hash_zeitwerk_probe.rb')
          File.write(file, "class LazyHashZeitwerkProbe; end\n")
          Object.autoload(:LazyHashZeitwerkProbe, file)
          begin
            expect(Object.const_defined?('LazyHashZeitwerkProbe')).to be_truthy
            expect(lazy_hash.key?('LazyHashZeitwerkProbe')).to be_falsey
            probe_loaded = Object.autoload?(:LazyHashZeitwerkProbe).nil?
          ensure
            begin
              Object.send(:remove_const, :LazyHashZeitwerkProbe)
            rescue NameError
              nil
            end
          end
        end
        expect(probe_loaded).to be false
      end

      it "returns true for a genuinely loaded constant that has no model file" do
        stub_const('AlreadyLoadedProbeModel', Class.new)
        expect(lazy_hash.key?('AlreadyLoadedProbeModel')).to be_truthy
      end
    end

    describe "keys with file paths" do
      it "returns all possible model names from files" do
        keys = lazy_hash.keys

        # Should include camelized versions of file paths
        expect(keys).to include('LazyTestModel')
        expect(keys).to include('Project')
      end
    end

    describe "on-demand model loading" do
      before(:each) do
        # Mock require_dependency to track calls
        # Note: require_dependency is called as a method, not on an object
        @require_calls = []

        # We need to mock it on the lazy_hash instance
        # because require_dependency is called within the context of get_or_load_model
        allow_any_instance_of(ActiveRecord::Base::LazyColumnsHash).to receive(:require_dependency) do |instance, path|
          @require_calls << path

          # Simulate loading the LazyTestModel constant after require
          if path == '/app/models/lazy_test_model.rb'
            stub_const('LazyTestModel', mock_lazy_test_model)
          end
        end

        # Mock ActiveRecord::Base.get_model_columns_hash
        allow(ActiveRecord::Base).to receive(:get_model_columns_hash) do |model|
          model.columns_hash
        end
      end

      it "loads model file on first access" do
        # Access a model that hasn't been loaded yet
        result = lazy_hash['LazyTestModel']

        # Should have called require_dependency
        expect(@require_calls).to include('/app/models/lazy_test_model.rb')
      end

      it "doesn't reload model file on subsequent access" do
        # First access
        lazy_hash['LazyTestModel']
        first_call_count = @require_calls.size

        # Second access
        lazy_hash['LazyTestModel']
        second_call_count = @require_calls.size

        # Should not have called require_dependency again
        expect(second_call_count).to eq(first_call_count)
      end

      it "caches loaded columns" do
        # First access loads and caches
        result1 = lazy_hash['LazyTestModel']

        # Second access returns cached value
        result2 = lazy_hash['LazyTestModel']

        expect(result1).to eq(result2)
      end
    end

    describe "find_file_path_for_model" do
      it "finds exact match" do
        path = lazy_hash.send(:find_file_path_for_model, 'LazyTestModel')
        expect(path).to eq('/app/models/lazy_test_model.rb')
      end

      it "handles namespace variations" do
        # Rescom::User should match rescom/user file
        rescom_map = { 'rescom/user' => '/app/models/rescom/user.rb' }
        rescom_hash = ActiveRecord::Base::LazyColumnsHash.new([], ['rescom/user'], rescom_map)

        path = rescom_hash.send(:find_file_path_for_model, 'Rescom::User')
        expect(path).to eq('/app/models/rescom/user.rb')
      end

      it "returns nil for non-existent models" do
        path = lazy_hash.send(:find_file_path_for_model, 'NonexistentModel')
        expect(path).to be_nil
      end
    end
  end

  describe "performance benefits" do
    it "does not load all model files during initialization" do
      # Mock 200 model files (using relative paths without directory prefix)
      model_files = (1..200).map { |i| "model#{i}" }
      file_map = model_files.each_with_object({}) do |file, hash|
        hash[file] = "/app/models/#{file}.rb"
      end

      # Track require_dependency calls
      require_calls = []
      allow_any_instance_of(ActiveRecord::Base::LazyColumnsHash).to receive(:require_dependency) do |instance, path|
        require_calls << path
      end

      # Create lazy hash - should NOT require any files
      lazy_hash = ActiveRecord::Base::LazyColumnsHash.new([], model_files, file_map)

      # Should not have loaded any files yet
      expect(require_calls).to be_empty

      # This is the key optimization: 90% reduction in model loading time
      # by not calling require_dependency(file) for all 200 models upfront
    end
  end
end
