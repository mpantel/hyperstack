# Deliberately standalone, like supported_versions_spec.rb and
# version_selectors_spec.rb: this is about what the esbuild pipeline WRITES into
# a package.json, which is plain Ruby and must be checkable on every line in the
# matrix -- including cells whose test_app cannot boot, and including the
# sprockets cells that never take the npm route at all.
#
# What it guards (#124): four React companion libraries ship in the client bundle
# of every generated app, they are pinned once for a matrix that is per-cell
# everywhere else, and until now nothing at all compared the two places those
# pins were written down.
require 'yaml'
require 'json'
require File.expand_path(
  '../../rails-hyperstack/lib/generators/hyperstack/js_pipeline/react_npm_dependencies',
  __dir__
)

describe Hyperstack::ReactNpmDependencies do
  ROOT = File.expand_path('../../..', __dir__)
  TABLE = File.join(ROOT, 'supported_versions.yml')

  # The two files that write a package.json for the esbuild pipeline. Both used
  # to carry their own heredoc of the same block.
  CONSUMERS = [
    File.join(ROOT, 'ruby/rails-hyperstack/lib/generators/hyperstack/js_pipeline/esbuild.rb'),
    File.join(ROOT, 'ruby/test_app_react_source.rb')
  ].freeze

  def self.series(value)
    value.to_s.split('.').first(2).join('.')
  end

  def series(value)
    self.class.series(value)
  end

  # `^19.2.0` / `~19.2.0` -> `19.2.0`. NOT String#delete('^~'): that argument is
  # tr-style set notation, where a leading ^ negates, so it deletes everything
  # that is not a tilde and returns ''.
  def bare(range)
    range.to_s.sub(/\A[\^~]/, '')
  end

  let(:cells) { YAML.safe_load(File.read(TABLE, encoding: 'UTF-8'))['cells'] }

  # The cells that actually take the npm route. The others get React from
  # react-rails over sprockets and never read any of this.
  let(:npm_cells) do
    cells.select { |c| (c['env'] || {})['HYPERSTACK_REACT_SOURCE'] == 'npm' }
  end

  around do |example|
    saved = ENV['REACT_NPM_VERSION']
    example.run
  ensure
    saved.nil? ? ENV.delete('REACT_NPM_VERSION') : (ENV['REACT_NPM_VERSION'] = saved)
  end

  def with_selector(value)
    value.nil? ? ENV.delete('REACT_NPM_VERSION') : (ENV['REACT_NPM_VERSION'] = value)
    yield
  end

  it 'finds the table and the cells it is meant to be guarding' do
    expect(File).to exist(TABLE)
    expect(npm_cells.map { |c| c['id'] }).to include('rails61-react19', 'rails72-react19')
  end

  describe 'the default React' do
    # The reason this spec exists at all. `^19.0.0` was stated in TWO Ruby files
    # and in no way connected to supported_versions.yml, which is the single
    # source of truth for every other version in the project. They agreed by
    # luck, and nothing would have noticed when they stopped.
    it 'names the same React series the npm cells run' do
      declared = npm_cells.map { |c| series(c['react']) }.uniq
      expect(declared.size).to eq(1),
                               "npm cells disagree about React: #{declared.inspect}. " \
                               'Pick the series DEFAULT_REACT_NPM_VERSION should name.'
      expect(series(bare(described_class::DEFAULT_REACT_NPM_VERSION)))
        .to eq(declared.first)
    end

    it 'is a caret range, so an unparameterised install takes the newest patch' do
      expect(described_class::DEFAULT_REACT_NPM_VERSION).to start_with('^')
    end

    it 'is used when no cell selects one' do
      with_selector(nil) do
        expect(described_class.react_version)
          .to eq described_class::DEFAULT_REACT_NPM_VERSION
      end
    end

    # #78's trap, on the npm side. An exported-but-empty selector is a cell that
    # left the key out; treated literally it would reach npm as `"react": ""`,
    # which yarn resolves to the LATEST react -- taking the cell off the React
    # axis it advertises, silently, in the direction of a version nobody tested.
    it 'is used when the selector is exported but blank' do
      ['', '   '].each do |blank|
        with_selector(blank) do
          expect(described_class.react_version)
            .to eq described_class::DEFAULT_REACT_NPM_VERSION
        end
      end
    end
  end

  describe 'per-cell selection' do
    it 'moves react and react-dom together, and nothing else' do
      pinned = with_selector(nil) { described_class.dependencies }
      selected = with_selector('~1.2.3') { described_class.dependencies }

      expect(selected['react']).to eq('~1.2.3')
      expect(selected['react-dom']).to eq('~1.2.3')
      # The whole point of #124: the companions are NOT on the React axis.
      companions = %w[create-react-class history react-router react-router-dom]
      expect(selected.slice(*companions)).to eq(pinned.slice(*companions))
    end

    it 'honours every REACT_NPM_VERSION the table actually sets' do
      npm_cells.each do |cell|
        selector = cell['env']['REACT_NPM_VERSION']
        expect(selector).not_to be_nil,
                                "#{cell['id']} takes the npm route but selects no REACT_NPM_VERSION"
        with_selector(selector) do
          expect(described_class.dependencies['react']).to eq(selector)
        end
        # cell_contract_spec reads window.React.version and compares it to the
        # cell's declared `react:`, so a selector that cannot resolve to that
        # series is a cell that will fail in the browser rather than here.
        expect(series(bare(selector))).to eq(series(cell['react'])),
                                                 "#{cell['id']}: REACT_NPM_VERSION #{selector.inspect} " \
                                                 "cannot resolve to react #{cell['react'].inspect}"
      end
    end
  end

  describe 'the companion pins' do
    # Not style rules -- each of these is a constraint with a failure mode, and
    # the module comment records which. Asserted so that changing one is a
    # deliberate act with this spec in the diff, rather than a tidy-up.
    it 'keeps history on the major react-router 5 itself depends on' do
      # react-router@5.3.4 depends on history ^4.9.0. A top-level history 5 would
      # install a SECOND copy nested under react-router, and window.History (what
      # React::Router::History reads) would then build histories the router
      # cannot consume.
      expect(described_class::HISTORY_VERSION).to start_with('^4.')
      expect(described_class::REACT_ROUTER_VERSION).to start_with('^5.')
    end

    it 'ships one react-router version for react-router and react-router-dom' do
      deps = described_class.dependencies
      expect(deps['react-router']).to eq(deps['react-router-dom'])
    end

    it 'keeps create-react-class, which every component is built with' do
      # react_wrapper.rb's create_native_react_class raises without it.
      expect(described_class.dependencies).to have_key('create-react-class')
    end

    it 'builds with esbuild and ships it to nobody' do
      expect(described_class.dev_dependencies).to have_key('esbuild')
      expect(described_class.dependencies).not_to have_key('esbuild')
    end
  end

  # The pin #125 moved, and the property that made moving it worth doing. Every
  # generated app inherits this devDependency, so it is also what every generated
  # app's `yarn audit` reports on -- and an audit finding on day one, on a
  # dependency the user did not choose, is the cost being removed here.
  #
  # Asserted as a RANGE rather than as a version. `^0.28.1` is not a pin to
  # 0.28.2; it is `>= 0.28.1, < 0.29.0`, and a fresh `yarn install` on a machine
  # with no lockfile takes whatever in that window is newest at the time. So the
  # question a spec has to answer is not "is the version we resolved today
  # clean?" but "is EVERY version this pin admits clean?" -- which is the
  # difference between `^0.28.1` and `^0.28.0`, the latter admitting 0.28.0 and
  # walking straight back into the second advisory.
  describe 'the esbuild pin' do
    # Both published esbuild advisories that have ever covered a version this
    # pin could reach, as half-open [floor, ceiling) intervals. Written out
    # rather than fetched: a spec that asks the network answers differently on a
    # runner with no egress, and these two windows are closed history -- they
    # describe releases that already happened and cannot change.
    ADVISORIES = [
      # "esbuild enables any website to send any requests to the development
      # server and read the response" -- affects <= 0.24.2, fixed in 0.25.0.
      # This is the one #125 exists to clear. NOT exploitable in a generated app
      # either way: it is a flaw in `esbuild serve`, and esbuild.config.js calls
      # .build() and never .serve(). `yarn audit` reports it regardless, which is
      # the whole point.
      { id: 'GHSA-67mh-4wv8-2f99', severity: 'moderate',
        floor: '0.0.0', ceiling: '0.24.3' },
      # The reason the floor below is 0.28.1 and not 0.28.0. Introduced in
      # 0.27.3, fixed in 0.28.1 -- a window entirely ABOVE the first advisory,
      # so "newer" is not by itself "clean" here.
      { id: 'GHSA-g7r4-m6w7-qqqr', severity: 'low',
        floor: '0.27.3', ceiling: '0.28.1' }
    ].freeze

    # npm's caret on a 0.x version is a single-minor range: `^0.28.1` is
    # `>= 0.28.1, < 0.29.0`, NOT `< 1.0.0`. Getting this wrong in the direction
    # of a wider range would make the spec pass on a pin it should reject, so it
    # is spelled out rather than approximated with Gem::Requirement's `~>`.
    def caret_range(pin)
      major, minor, = bare(pin).split('.').map(&:to_i)
      floor = Gem::Version.new(bare(pin))
      ceiling = major.zero? ? "0.#{minor + 1}.0" : "#{major + 1}.0.0"
      [floor, Gem::Version.new(ceiling)]
    end

    it 'is a caret on a 0.x version, the shape the range logic assumes' do
      # If the pin ever becomes `>=0.28`, `0.28.x` or a 1.x, caret_range above is
      # answering a question that was not asked and the overlap check below is
      # worthless. Fail loudly instead of passing vacuously.
      expect(described_class::ESBUILD_VERSION).to match(/\A\^0\.\d+\.\d+\z/)
    end

    it 'admits no version inside a published advisory window' do
      floor, ceiling = caret_range(described_class::ESBUILD_VERSION)

      ADVISORIES.each do |advisory|
        low = Gem::Version.new(advisory[:floor])
        high = Gem::Version.new(advisory[:ceiling])
        # Two half-open intervals overlap iff each starts before the other ends.
        overlaps = floor < high && low < ceiling
        expect(overlaps).to be(false),
                            "esbuild #{described_class::ESBUILD_VERSION} resolves within " \
                            "[#{floor}, #{ceiling}), which overlaps #{advisory[:id]} " \
                            "(#{advisory[:severity]}, [#{low}, #{high})). Every generated " \
                            "app would report this in `yarn audit`. Raise the pin's floor " \
                            "above #{high} rather than relying on which version happens " \
                            'to resolve today. (#125)'
      end
    end

    it 'would have caught the pin it replaced, and the near miss beside it' do
      # The guard above is only worth its lines if it actually rejects something.
      # `^0.23.0` is what #125 removed; `^0.28.0` is the plausible way to get this
      # wrong while believing you had fixed it. Both must be seen as overlapping.
      %w[^0.23.0 ^0.24.0 ^0.27.5 ^0.28.0].each do |bad|
        floor, ceiling = caret_range(bad)
        hit = ADVISORIES.any? do |a|
          floor < Gem::Version.new(a[:ceiling]) && Gem::Version.new(a[:floor]) < ceiling
        end
        expect(hit).to be(true), "#{bad} should be rejected by the advisory check but is not"
      end
    end
  end

  describe 'the generated package.json' do
    it 'is valid JSON with the name it was asked for' do
      parsed = JSON.parse(described_class.package_json(name: 'my_app'))
      expect(parsed['name']).to eq('my_app')
      expect(parsed['private']).to be true
      expect(parsed['scripts']).to eq('build' => 'node esbuild.config.js')
      expect(parsed['dependencies']).to eq(described_class.dependencies)
      expect(parsed['devDependencies']).to eq(described_class.dev_dependencies)
    end

    it 'differs between the two consumers only in the app name' do
      # The generator names the app after Rails.root; the test-app harness calls
      # it test_app. Everything else must be identical, because a suite proving a
      # dependency set no generated app has is proving nothing.
      generated = JSON.parse(described_class.package_json(name: 'some_app'))
      test_app = JSON.parse(described_class.package_json(name: 'test_app'))
      expect(generated.reject { |k, _| k == 'name' })
        .to eq(test_app.reject { |k, _| k == 'name' })
    end
  end

  describe 'the consumers' do
    # The guard that keeps this file meaningful. Both consumers reached the same
    # values by hand-maintained heredoc; if one grows a literal pin again, the
    # module stops being the single source and nothing else would say so.
    #
    # Checked to fail: adding `"react-router": "^5.3.4"` back into either file
    # trips this.
    it 'do not restate any pin the module owns' do
      literals = [
        described_class::DEFAULT_REACT_NPM_VERSION,
        described_class::ESBUILD_VERSION,
        described_class::REACT_ROUTER_VERSION,
        described_class::HISTORY_VERSION,
        described_class::CREATE_REACT_CLASS_VERSION
      ]
      CONSUMERS.each do |path|
        body = File.read(path, encoding: 'UTF-8')
        literals.each do |literal|
          expect(body).not_to include(%("#{literal}")),
                              "#{File.basename(path)} hard-codes #{literal.inspect}; " \
                              'it belongs to Hyperstack::ReactNpmDependencies (#124)'
        end
      end
    end

    it 'both route through the module' do
      CONSUMERS.each do |path|
        expect(File.read(path, encoding: 'UTF-8'))
          .to include('ReactNpmDependencies'),
              "#{File.basename(path)} no longer uses the shared dependency set (#124)"
      end
    end

    # The one that was actually wrong: a package.json declaring react ^15.6.1 and
    # react-router ^4.2.0, read by nothing, two majors below the matrix floor.
    # Its true content -- the provenance of the vendored UMDs -- now lives in
    # react-router-source.rb next to the files it describes.
    it 'leave no unread package.json in the gems' do
      strays = Dir[File.join(ROOT, 'ruby', '*', 'package.json')]
      expect(strays).to be_empty,
                        "unread package.json: #{strays.map { |p| p.sub("#{ROOT}/", '') }.inspect}"
    end
  end
end
