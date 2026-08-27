# Deliberately standalone, like supported_versions_spec.rb: this is about how the
# gemspecs evaluate, so it must not need a booted test_app.
#
# Every gemspec is evaluated in a SUBPROCESS. Gem::Specification.load memoises per
# path, so a second call in one process hands back the first call's result and
# every ENV-varying example here would pass vacuously against a stale spec. A
# fresh process per case also keeps twelve gemspecs from redefining each other's
# VERSION constants, and is what `bundle install` actually does. (#78)
require 'json'
require 'rbconfig'
require File.expand_path('../../version_selector', __dir__)

module VersionSelectorSpecHelper
  ROOT = File.expand_path('../../..', __dir__)
  GEMSPECS = Dir[File.join(ROOT, 'ruby', '*', '*.gemspec')].sort.freeze

  # selector -> the dependency it pins. OPAL_SPROCKETS_VERSION is the odd one:
  # it does not just pin a version, it swaps opal-sprockets in for opal-rails,
  # which is the only route to sprockets on Rails 8. (#20)
  SELECTORS = {
    'RAILS_VERSION' => 'rails',
    'OPAL_VERSION' => 'opal',
    'OPAL_RAILS_VERSION' => 'opal-rails',
    'OPAL_SPROCKETS_VERSION' => 'opal-sprockets',
    'REACT_RAILS_VERSION' => 'react-rails',
    'SQLITE3_VERSION' => 'sqlite3'
  }.freeze

  EVAL_SCRIPT = <<~RUBY
    require 'json'
    spec = eval(File.read(ARGV[0]), TOPLEVEL_BINDING, ARGV[0])
    puts JSON.generate(spec.dependencies.to_h { |d| [d.name, d.requirement.to_s] })
  RUBY

  module_function

  # The child must NOT inherit bundler's environment. Under `bundle exec` RUBYOPT
  # carries -rbundler/setup, so the child resolves the whole bundle before it ever
  # reaches the gemspec -- and since these examples deliberately export things like
  # RAILS_VERSION=9.9.9, that resolution dies with
  #
  #   Bundler::GemNotFound: Could not find gem 'rails (= 9.9.9)' in locally
  #   installed gems
  #
  # which is bundler refusing a version nobody installed, not the gemspec failing to
  # evaluate. Run bare: evaluating a gemspec needs rubygems and nothing else.
  # (Plain `rspec` sets none of this, which is why it only shows under bundler.)
  def unbundled_env
    ENV.keys.grep(/\A(BUNDLE|BUNDLER)/).to_h { |k| [k, nil] }
       .merge('RUBYOPT' => nil, 'RUBYLIB' => nil)
  end

  # nil unsets the variable in the child, which is what "not selected" means.
  def requirements_for(path, overrides = {})
    @cache ||= {}
    key = [path, overrides]
    return @cache[key] if @cache.key?(key)

    env = SELECTORS.keys.to_h { |k| [k, nil] }.merge(unbundled_env).merge(overrides)
    out = nil
    IO.popen(env, [RbConfig.ruby, '-e', EVAL_SCRIPT, path],
             chdir: File.dirname(path), err: %i[child out]) { |io| out = io.read }
    unless $?.success? # rubocop:disable Style/SpecialGlobalVars
      raise "#{File.basename(path)} failed to evaluate with #{overrides.inspect}:\n#{out}"
    end

    @cache[key] = JSON.parse(out)
  end

  def with_env(vars)
    saved = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : (ENV[k] = v) }
  end
end

describe 'gemspec version selectors' do
  include VersionSelectorSpecHelper
  H = VersionSelectorSpecHelper

  it 'finds the gemspecs it is meant to be guarding' do
    expect(H::GEMSPECS.map { |p| File.basename(p) }).to include(
      'hyper-component.gemspec', 'hyper-model.gemspec', 'hyper-spec.gemspec',
      'hyperstack-config.gemspec', 'rails-hyperstack.gemspec'
    )
  end

  describe 'Hyperstack.version_selector' do
    it 'returns the defaults when the variable is absent' do
      expect(Hyperstack.version_selector('HS_ABSENT_XYZ', '>= 5.0.0', '< 7.0'))
        .to eq ['>= 5.0.0', '< 7.0']
    end

    it 'treats an exported-but-empty value as absent' do
      # the whole point: '' is truthy in Ruby, so the old idiom selected on it
      # and produced the requirement [''] -> "Illformed requirement"
      with_env('HS_BLANK_XYZ' => '') do
        expect(Hyperstack.version_selector('HS_BLANK_XYZ', '~> 2.0')).to eq ['~> 2.0']
      end
    end

    it 'treats a whitespace-only value as absent' do
      with_env('HS_WS_XYZ' => "  \t ") do
        expect(Hyperstack.version_selector('HS_WS_XYZ', '~> 2.0')).to eq ['~> 2.0']
      end
    end

    it 'selects a real value, and strips it' do
      with_env('HS_SET_XYZ' => ' 6.1.7.10 ') do
        expect(Hyperstack.version_selector('HS_SET_XYZ', '~> 2.0')).to eq ['6.1.7.10']
      end
    end
  end

  H::GEMSPECS.each do |path|
    describe File.basename(path) do
      let(:source) { File.read(path) }

      it 'requires the shared selector helper' do
        expect(source).to include "require_relative '../version_selector'"
      end

      it 'does not reuse the old truthy-ENV idiom' do
        # a copy-pasted `ENV['X'] ? [ENV['X']] : [...]` would reintroduce the bug
        # in one gemspec while every other guard here still passed
        expect(source).not_to match(/ENV\['[A-Z_]+_VERSION'\]\s*\?/)
      end

      it 'evaluates with no selectors set' do
        expect(requirements_for(path)).to be_a(Hash)
      end

      it 'resolves identically whether the selectors are blank or absent' do
        blank = H::SELECTORS.keys.to_h { |k| [k, ''] }
        expect(requirements_for(path, blank)).to eq requirements_for(path)
      end

      it 'resolves identically whether the selectors are whitespace or absent' do
        ws = H::SELECTORS.keys.to_h { |k| [k, '   '] }
        expect(requirements_for(path, ws)).to eq requirements_for(path)
      end

      # Only for the selectors this gemspec actually declares -- defined
      # conditionally rather than skipped inside the example, so a gemspec that
      # silently stopped reading a selector fails instead of vanishing.
      H::SELECTORS.each do |var, dep|
        next unless File.read(path).include?(var)

        it "reads #{var} and pins #{dep} with it" do
          expect(requirements_for(path, var => '9.9.9')[dep]).to eq '= 9.9.9'
        end
      end

      if File.read(path).include?('OPAL_SPROCKETS_VERSION')
        it 'swaps opal-sprockets IN and opal-rails OUT, not merely pinning' do
          # opal-rails 2.x is capped at `rails < 7.3`, so on the Rails 8 cell it
          # must not be in the bundle at all -- pinning opal-sprockets while
          # leaving opal-rails behind would still fail to resolve. (#20)
          swapped = requirements_for(path, 'OPAL_SPROCKETS_VERSION' => '9.9.9')
          expect(swapped).to include('opal-sprockets' => '= 9.9.9')
          expect(swapped).not_to have_key('opal-rails')

          # and with it unset, the default route is opal-rails and nothing else
          default = requirements_for(path)
          expect(default).to have_key('opal-rails')
          expect(default).not_to have_key('opal-sprockets')
        end
      end
    end
  end
end
