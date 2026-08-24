require 'spec_helper'
require 'rspec-steps'

# The steps below run as a single shared-session RSpec::Steps sequence inside one
# long-lived browser. The aliases under test are installed on the client via
# `before(:step) { isomorphic/on_client { User.alias_attribute ... } }`, where
# `on_client`/`isomorphic` inject code only at *mount* time. Because the whole
# sequence runs inside one example, that injection effectively happens once (on
# the first step's mount) and then has to survive for the rest of the run. If
# hyper-spec re-mounts/reloads the page mid-sequence -- `insure_page_loaded`
# reloads whenever `Opal` momentarily looks absent (a transient `evaluate_script`
# hiccup is swallowed and treated as "Opal missing") -- the page is replaced and
# the aliases are gone, so a later step blows up with
# `undefined method 'surname_changed?'` (#25). This is the same mount-injection
# lifetime flake hardened in hyper-operation/execution_spec.rb (7c3e545ba).
#
# `alias_attribute` installs BOTH the explicit alias methods AND the
# `_attribute_aliases` entry in the same call (ReactiveRecord ClassMethods), so a
# wiped injection takes the `method_missing` dealias fallback down with it --
# which is why the deterministic dealias (#25) alone did not stop the flake.
#
# Fix (spec-only): (re)define the client aliases immediately before *every* client
# evaluation. Run `insure_page_loaded` first (performing any pending re-mount up
# front), then re-install the aliases as a standalone top-level script, then call
# super; by then Opal is loaded so super's own `insure_page_loaded` is a no-op and
# cannot wipe them. All eval entry points the spec uses
# (expect_evaluate_ruby/expect_promise and evaluate_promise) funnel through
# `evaluate_ruby`, so that is the seam we hook (overriding `internal_evaluate_ruby`
# would be invisible to callers that invoke the alias).
module HyperspecAliasAttributeClientSetup
  CLIENT_ALIASES = <<~RUBY
    class SubUser < User; end unless defined?(SubUser)
    User.alias_attribute :surname, :last_name
    User.alias_attribute :client_name, :last_name
  RUBY

  module Prepended
    def evaluate_ruby(*args, &block)
      insure_page_loaded
      page.execute_script(opal_compile(CLIENT_ALIASES))
      super(*args, &block)
    end
  end

  def self.included(base)
    base.prepend(Prepended)
  end
end

RSpec::Steps.steps 'alias_attribute', js: true do

  include HyperspecAliasAttributeClientSetup

  before(:each) do
    require 'pusher'
    require 'pusher-fake'
    Pusher.app_id = "MY_TEST_ID"
    Pusher.key =    "MY_TEST_KEY"
    Pusher.secret = "MY_TEST_SECRET"
    require "pusher-fake/support/base"

    Hyperstack.configuration do |config|
      config.transport = :pusher
      config.channel_prefix = "synchromesh"
      config.opts = {app_id: Pusher.app_id, key: Pusher.key, secret: Pusher.secret, use_tls: false}.merge(PusherFake.configuration.web_options)
    end

  end

  before(:step) do
    stub_const 'TestApplicationPolicy', Class.new
    TestApplicationPolicy.class_eval do
      always_allow_connection
      regulate_all_broadcasts { |policy| policy.send_all }
      allow_change(to: :all, on: [:create, :update, :destroy]) { true }
    end
    ApplicationController.acting_user = nil
    isomorphic do
      User.alias_attribute :surname, :last_name
      class SubUser < User
      end
    end
    on_client do
      # Aliases are implemented as method aliases.  However these will not
      # work with class methods like create, so we also keep a hash of aliases
      # associated with the class.
      # In order to test alias inheritence we will just add this alias on the
      # client.  Thus if during any access we DID not inherit the alias
      # it will remain as client_name, which will break the server side store
      User.alias_attribute :client_name, :last_name
    end
  end

  it "implements find_by" do
    @user = User.create(first_name: "Mitch", last_name: "VanDuyn")
    expect_promise do
      ReactiveRecord.load { User.find_by(first_name: "Mitch", surname: "VanDuyn").id }
    end.to eq(@user.id)
  end

  it "implements the finder" do
    @user = User.create(first_name: "M.", last_name: "Pantel")
    expect_promise do
      ReactiveRecord.load { User.find_by_surname('Pantel').id }
    end.to eq(@user.id)
  end

  it "works with find_by without fetching from the DB" do
    expect_evaluate_ruby do
      User.find_by(first_name: 'M.', last_name: 'Pantel').id
    end.to eq(@user.id)
  end

  it "implements the getter" do
    expect_promise do
      ReactiveRecord.load { User.find_by_first_name('M.').surname }
    end.to eq('Pantel')
  end

  it "implements the setter" do
    evaluate_promise do
      user = User.find_by_first_name('M.')
      user.surname = "Someoneelse"
      user.save
    end
    expect(@user.reload.surname).to eq('Someoneelse')
  end

  it "implements the _changed? method" do
    expect_evaluate_ruby do
      user = User.find_by_first_name('M.')
      user.last_name = "Pantel"
      user.surname_changed?
    end.to be_truthy
  end

  it "can inherit the aliases" do
    evaluate_promise do
      SubUser.create(client_name: 'Fred')
    end
    expect(SubUser.find_by_surname('Fred')).to be_truthy
  end

  it "resolves aliased attribute methods via method_missing when the alias method is absent" do
    # Regression for #25: alias_attribute defines explicit alias methods, but they
    # can race with the spec's isomorphic propagation to the client. Remove them so
    # the dealias fallback in method_missing is the only path — proving aliased
    # getter/setter/_changed? resolve to the real column without the explicit alias.
    expect_evaluate_ruby do
      %i[surname surname= surname! surname? surname_changed?].each do |m|
        User.send(:remove_method, m) if User.instance_methods(false).include?(m)
      end
      user = User.find_by_first_name('M.')
      user.surname = 'Reached'
      [user.surname, user.surname_changed?]
    end.to eq(['Reached', true])
  end

end
