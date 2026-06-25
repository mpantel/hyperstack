require 'spec_helper'

# Regression coverage for #2: a spec ivar holding a *collection* of
# unserializable objects must not emit invalid Opal (e.g. `[, , ,]` /
# `{ => }`), which raised Opal::SyntaxError and broke every mount-based spec.
# Array#/Hash#opal_serialize now return nil when any element can't be
# serialized, so set_local_var emits the safe "unserializable" stub instead.
describe 'opal_serialize for collections' do
  it 'serializes collections whose members all serialize' do
    expect([].opal_serialize).to eq('[]')
    expect({}.opal_serialize).to eq('{}')
    expect([[], {}].opal_serialize).to eq('[[], {}]')
    expect({ [] => {} }.opal_serialize).to eq('{[] => {}}')
  end

  it 'returns nil when an array contains an unserializable element' do
    expect([Object.new].opal_serialize).to be_nil
    expect([Object.new, Object.new].opal_serialize).to be_nil
    expect([[], Object.new].opal_serialize).to be_nil # mixed: one serializes, one doesn't
  end

  it 'returns nil when a hash has an unserializable key or value' do
    expect({ [] => Object.new }.opal_serialize).to be_nil # bad value
    expect({ Object.new => [] }.opal_serialize).to be_nil # bad key
  end
end
