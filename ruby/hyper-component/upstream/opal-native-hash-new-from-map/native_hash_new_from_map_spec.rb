# Independent reproduction for an Opal `native` stdlib bug.
#
# Bug: `Hash.new(source)` from the `native` stdlib populates correctly when
# `source` is a Map-backed Opal Hash, but forgets to `return self`, so it falls
# through to MRI `Hash#initialize` and sets `source` as the hash's *default
# value*. Missing keys then return the whole source hash instead of `nil`.
#
# This spec depends ONLY on Opal + its `native` stdlib (no Hyperstack), so it can
# be dropped into the Opal repo's spec suite to drive/verify an upstream fix.
#
# Run (in a checkout of opal):
#   bundle exec rake mspec_node   # or the project's JS-runtime spec task
#
# Expected: all examples pass once stdlib/native.rb's Map branch `return self`s.
# Before the fix: the "missing key" / "default" examples fail.

require 'native'

describe 'native Hash.new(source) where source is a Map-backed Opal Hash' do
  let(:source) { { 'a' => 1, 'b' => 2 } }
  let(:copy)   { Hash.new(source) }

  it 'populates the copy from the source entries' do
    copy['a'].should == 1
    copy['b'].should == 2
    copy.keys.sort.should == ['a', 'b']
  end

  it 'returns nil for a missing key (not the source hash)' do
    copy['missing'].should be_nil
  end

  it 'leaves the default value as nil (not the source hash)' do
    copy.default.should be_nil
  end

  it 'reports key? correctly and consistently with []' do
    copy.key?('missing').should == false
    copy['missing'].should be_nil
  end

  it 'corrects nested Map values recursively' do
    nested = Hash.new({ 'outer' => { 'inner' => 1 } })
    nested['outer']['inner'].should == 1
    nested['outer']['missing'].should be_nil
    nested['missing'].should be_nil
  end

  it 'still treats a non-container default as a real default value' do
    counting = Hash.new(0)
    counting['never_set'].should == 0
  end

  it 'still honors a default block' do
    blocky = Hash.new { |h, k| k.to_s * 2 }
    blocky['x'].should == 'xx'
  end
end
