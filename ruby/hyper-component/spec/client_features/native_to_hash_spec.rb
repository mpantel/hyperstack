require 'spec_helper'

# Regression specs for issue #24: under Opal 1.8 the `native` stdlib's
# `Hash.new(map)` populates from a Map-backed Opal Hash but leaks the source as
# the hash's default value, so missing keys returned the whole source hash
# instead of nil. hyper-component patches `Hash#initialize` (see
# lib/hyperstack/internal/component/native_to_hash.rb). These run in the browser.
describe 'Opal 1.8 native Hash.new(map) default leak (issue #24)', js: true do
  it 'Hash.new from a Map-backed Opal Hash does not leak the source as default' do
    expect_evaluate_ruby do
      copy = Hash.new({ 'a' => 1, 'b' => 2 })
      [copy['a'], copy['missing'].nil?, copy.default.nil?, copy.key?('missing')]
    end.to eq([1, true, true, false])
  end

  it 'native_to_hash keeps nil semantics for missing nested keys' do
    expect_evaluate_ruby do
      native = { 'outer' => { 'inner' => 1 } }.to_n
      h = Hyperstack::Internal::Component.native_to_hash(native)
      [h['outer']['inner'], h['outer']['missing'].nil?, h['missing'].nil?]
    end.to eq([1, true, true])
  end

  it 'still treats a non-container default and a default block normally' do
    expect_evaluate_ruby do
      [Hash.new(0)['x'], (Hash.new { |h, k| k.to_s * 2 })['z']]
    end.to eq([0, 'zz'])
  end

  it 'reproduces the addons Pager trigger: missing :filter on a column is falsy' do
    expect_evaluate_ruby do
      columns = { 'id' => { 'description' => 'MK', 'key' => true } }.to_n
      h = Hyperstack::Internal::Component.native_to_hash(columns)
      # mirrors Pager#filters: select columns whose :filter is set
      h.select { |_field, contents| contents[:filter] }.empty?
    end.to be_truthy
  end
end
