require 'spec_helper'
require 'yaml'

# Does this cell actually run what supported_versions.yml advertises?
#
# `rake hyperstack:matrix:check` only proves the table and the CI cell list name
# the same cells. Nothing proved that a cell claiming `react: "16.14"` was in
# fact running React 16.14 -- and it turned out one was not, because the value
# was derived by reading package.json rather than by looking at the browser.
#
# This closes that gap: for whichever cell CI is currently running, assert the
# versions actually loaded. A cell that drifts from its declaration now fails
# here instead of being discovered months later while debugging something else.
#
# Skipped when HYPERSTACK_CELL is unset, so local runs are unaffected.
describe 'the running cell matches supported_versions.yml' do
  CELL_ID = ENV['HYPERSTACK_CELL']
  TABLE   = File.expand_path('../../../supported_versions.yml', __dir__)

  # major.minor only: the table records the series, not the patch.
  def self.series(value)
    return nil if value.nil?

    value.to_s.split('.').first(2).join('.')
  end

  def series(value)
    self.class.series(value)
  end

  let(:cell) do
    cells = YAML.safe_load(File.read(TABLE, encoding: 'UTF-8'))['cells']
    cells.detect { |c| c['id'] == CELL_ID } ||
      raise("HYPERSTACK_CELL=#{CELL_ID.inspect} is not in supported_versions.yml")
  end

  before { skip 'HYPERSTACK_CELL not set (local run)' unless CELL_ID }

  it 'runs the advertised Ruby' do
    expect(series(RUBY_VERSION)).to eq(series(cell['ruby']))
  end

  it 'runs the advertised Rails' do
    skip 'Rails not loaded in this gem' unless defined?(::Rails::VERSION::STRING)
    expect(series(::Rails::VERSION::STRING)).to eq(series(cell['rails']))
  end

  it 'runs the advertised Opal' do
    skip 'Opal not loaded in this gem' unless defined?(::Opal::VERSION)
    expect(series(::Opal::VERSION)).to eq(series(cell['opal']))
  end

  it 'runs the advertised react-rails' do
    skip 'react-rails not loaded in this gem' unless defined?(::React::Rails::VERSION)
    expect(series(::React::Rails::VERSION)).to eq(series(cell['react_rails']))
  end

  # The one axis that cannot be read server-side. `react` is DERIVED -- whatever
  # react_rails + the JS pipeline actually put on window -- so the browser is the
  # only authority, and reading it here is the whole point of this file.
  it 'serves the advertised React to the browser', js: true do
    mount 'SayHello', name: 'Fred'
    actual = page.evaluate_script('(window.React && window.React.version) || null')
    expect(actual).not_to be_nil, 'window.React is undefined — no React reached the browser'
    $stdout.puts "[CELL] #{CELL_ID}: window.React.version=#{actual.inspect} " \
                 "declared=#{cell['react'].inspect}"
    $stdout.flush
    expect(series(actual)).to eq(series(cell['react']))
  end
end
