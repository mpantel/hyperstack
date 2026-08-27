require 'spec_helper'
require 'test_components'

# Pins the contract investigated in issue #45.
#
# Some downstream apps declare a polymorphic `belongs_to` on the server only:
#
#   belongs_to :owner, polymorphic: true unless RUBY_ENGINE == 'opal'
#
# hyper-model does not require that guard -- poly_assoc_spec.rb declares the same
# association isomorphically and passes. When an app does use it, the association is
# rebuilt on the client by `AssociationReflection#find_inverse`'s dynamic-add fallback
# (hyperstack-org/hyperstack#89), but only as a side effect of resolving the inverse of
# the `has_many ..., as:` side.
#
# So the guard buys a client API that is order dependent:
#   * walking the has_many `as:` side works, and rebuilds the belongs_to on the way,
#   * once rebuilt the belongs_to reads and writes normally,
#   * but reach for the belongs_to first and it silently degrades to a plain attribute
#     fetch that yields the owner's column hash instead of a model.
#
# Declaring the belongs_to on both sides avoids all of this, which is why the guard is
# documented as a compatibility fallback rather than a recommended pattern.
describe 'polymorphic belongs_to guarded away from the client', js: true do
  before(:all) do
    require 'pusher'
    require 'pusher-fake'
    Pusher.app_id = 'MY_TEST_ID'
    Pusher.key =    'MY_TEST_KEY'
    Pusher.secret = 'MY_TEST_SECRET'
    require 'pusher-fake/support/base'

    Hyperstack.configuration do |config|
      config.transport = :pusher
      config.channel_prefix = 'synchromesh'
      config.opts = { app_id: Pusher.app_id, key: Pusher.key, secret: Pusher.secret, use_tls: false }
                    .merge(PusherFake.configuration.web_options)
    end

    class ActiveRecord::Base
      class << self
        def public_columns_hash
          @public_columns_hash ||= {}
        end
      end
    end
  end

  before(:each) do
    stub_const 'TestApplicationPolicy', Class.new
    TestApplicationPolicy.class_eval do
      always_allow_connection
      regulate_all_broadcasts { |policy| policy.send_all }
      allow_change(to: :all, on: [:create, :update, :destroy]) { true }
    end

    size_window(:small, :large)

    isomorphic do
      class Cabinet < ActiveRecord::Base
        def self.build_tables
          connection.create_table :cabinets, force: true do |t|
            t.string :name
            t.timestamps
          end
          ActiveRecord::Base.public_columns_hash[name] = columns_hash
        end

        has_many :attached_files, as: :owner
      end

      class AttachedFile < ActiveRecord::Base
        def self.build_tables
          connection.create_table :attached_files, force: true do |t|
            t.string :name
            t.integer :owner_id
            t.string :owner_type
            t.timestamps
          end
          ActiveRecord::Base.public_columns_hash[name] = columns_hash
        end

        # the pattern under investigation: declared on the server, skipped on the client
        belongs_to :owner, polymorphic: true unless RUBY_ENGINE == 'opal'
      end
    end

    [Cabinet, AttachedFile].each(&:build_tables)

    @cabinet = Cabinet.create(name: 'cabinet1')
    @file1 = AttachedFile.create(name: 'file1', owner: @cabinet)
    @file2 = AttachedFile.create(name: 'file2', owner: @cabinet)
  end

  it 'does not define the belongs_to accessor on the client' do
    expect_evaluate_ruby do
      AttachedFile.reflect_on_association(:owner).nil?
    end.to be_truthy
  end

  it 'reading the has_many `as:` side still works' do
    expect_promise do
      Hyperstack::Model.load { Cabinet.find(1).attached_files.collect(&:name) }
    end.to contain_exactly('file1', 'file2')
  end

  it 'walking the has_many `as:` side reconstructs the belongs_to on the client' do
    expect_promise do
      Hyperstack::Model.load { Cabinet.find(1).attached_files.collect(&:name) }
              .then { AttachedFile.reflect_on_association(:owner)&.polymorphic? }
    end.to be_truthy
  end

  it 'the reconstructed belongs_to reads back through the polymorphic owner' do
    expect_promise do
      Hyperstack::Model.load { Cabinet.find(1).attached_files.collect(&:name) }
              .then { Hyperstack::Model.load { AttachedFile.find(1).owner.name } }
    end.to eq('cabinet1')
  end

  it 'the reconstructed belongs_to can be written from the client' do
    other = Cabinet.create(name: 'cabinet2')
    evaluate_promise do
      Hyperstack::Model.load { Cabinet.find(1).attached_files.collect(&:name) }
              .then do
                f = AttachedFile.find(1)
                f.owner = Cabinet.find(2)
                f.save
              end
    end
    wait_for_ajax
    other.reload
    expect(other.attached_files.collect(&:name)).to eq(['file1'])
  end

  it 'warns in a way that names the fix' do
    evaluate_promise do
      Hyperstack::Model.load { Cabinet.find(1).attached_files.collect(&:name) }
    end
    warnings = page.driver.browser.logs.get(:browser)
                   .select { |entry| entry.level == 'WARNING' }
                   .collect(&:message)
    expect(warnings).to include(
      a_string_including('dynamically adding relationship: AttachedFile.belongs_to :owner, polymorphic: true')
        .and(a_string_including('declare it in AttachedFile to avoid this'))
    )
  end

  it 'silently degrades the belongs_to to a raw attribute fetch until the inverse is resolved' do
    # Without the reflection there is no association to read, so `owner` falls through
    # to method_missing and is fetched as if it were a plain attribute: the client gets
    # back the owner's serialized column hash instead of a Cabinet, and any model method
    # on it (here `name`) blows up with `undefined method`.
    expect_promise do
      Hyperstack::Model.load { AttachedFile.find(1).owner }
              .then { |owner| [owner.class.name, owner.respond_to?(:name)] }
    end.to eq(['Hash', false])
  end
end
