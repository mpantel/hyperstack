require 'spec_helper'
require 'rspec-steps'

RSpec::Steps.steps 'the where method and class delegation', js: true do

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
      User.class_eval do
        def self.with_size(attr, size)
          where("LENGTH(#{attr}) = ?", size)
        end
      end
    end

    @user1 = User.create(first_name: "Mitch", last_name: "VanDuyn")
    User.create(first_name: "Joe", last_name: "Blow")
    @user2 = User.create(first_name: "Jan", last_name: "VanDuyn")
    User.create(first_name: "Ralph", last_name: "HooBo")
  end

  it "can take a hash like value" do
    client_option raise_on_js_errors: :debug
    expect do
      ReactiveRecord.load { User.where(surname: "VanDuyn").pluck(:id, :first_name) }
    end.on_client_to eq User.where(surname: "VanDuyn").pluck(:id, :first_name)
  end

  it "and will update the collection on the client " do
    # #70 DIAGNOSTICS -- debug branch, not for merge.
    #
    # This step creates a record server-side and expects the client's
    # already-loaded collection to update over pusher-fake. It fails on most full
    # matrix runs, on every cell, and `on_client_to` polls -- so the broadcast is
    # not merely late, it never arrives.
    #
    # Two candidates, which these prints separate:
    #   a) nobody was listening   -> `channels:` is empty / lacks the client's
    #                                channel at create time (subscription race)
    #   b) sent but not received  -> channels look right and send_to_channel is
    #                                called, but the client never applies it
    #
    # show_diagnostics also turns on, in the library:
    #   active_record_base.rb:351  synchromesh_after_create + Connection.active
    #   broadcast.rb:9             "Broadcast aftercommit hook: <data>"
    #   connection.rb              open / send_to_channel / read / connect_to_transport
    begin
      $stdout.puts "[#70] channels BEFORE create: #{Hyperstack::Connection.active.inspect}"
      $stdout.flush
      Hyperstack::Connection.show_diagnostics = true

      User.create(first_name: "Paul", last_name: "VanDuyn")

      $stdout.puts "[#70] channels AFTER create: #{Hyperstack::Connection.active.inspect}"
      $stdout.puts "[#70] server sees: #{User.where(surname: "VanDuyn").pluck(:id, :first_name).inspect}"
      $stdout.flush

      expect do
        User.where(surname: "VanDuyn").pluck(:id, :first_name)
      end.on_client_to eq User.where(surname: "VanDuyn").pluck(:id, :first_name)
    ensure
      # Report the client's final view either way, so a PASSING run gives us a
      # baseline to compare the failing one against.
      $stdout.puts "[#70] client finally sees: " \
                   "#{evaluate_ruby('User.where(surname: "VanDuyn").pluck(:id, :first_name)').inspect}"
      $stdout.puts "[#70] channels AT END: #{Hyperstack::Connection.active.inspect}"
      $stdout.flush
      Hyperstack::Connection.show_diagnostics = false
    end
  end

  it "or it can take SQL plus params" do
    expect do
      Hyperstack::Model.load { User.where("first_name LIKE ?", "J%").pluck(:first_name, :surname) }
    end.on_client_to eq User.where("first_name LIKE ?", "J%").pluck(:first_name, :surname)
  end

  it "class methods will be called from collections" do
    expect do
      Hyperstack::Model.load { User.where(last_name: 'VanDuyn').with_size(:first_name, 3).pluck('first_name') }
    end.on_client_to eq User.where(last_name: 'VanDuyn').with_size(:first_name, 3).pluck('first_name')
  end

  it "where-s can be chained (cause they are just class level methods after all)" do
    expect do
      Hyperstack::Model.load { User.where(last_name: 'VanDuyn').where(first_name: 'Jan').pluck(:id) }
    end.on_client_to eq User.where(last_name: 'VanDuyn', first_name: 'Jan').pluck(:id)
  end

end
