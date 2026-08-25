require 'spec_helper'
require 'test_components'

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

end
