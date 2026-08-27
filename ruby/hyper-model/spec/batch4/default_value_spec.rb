require 'spec_helper'

# The two components mounted here live in spec/support/default_value_components.rb --
# they are shared by more than one example, and keeping a copy per example is what
# produced default_value_textarea_spec.rb, a 248-line duplicate of this file that
# existed to carry two assertions and had already drifted from it (#62).

describe 'defaultValue special handling', js: true do

  before(:all) do
    ReactiveRecord::Operations::Fetch.class_eval do
      def self.semaphore
        @semaphore ||= Mutex.new
      end
      validate { self.class.semaphore.synchronize { true } }
    end
    require 'pusher'
    require 'pusher-fake'
    Pusher.app_id = "MY_TEST_ID"
    Pusher.key =    "MY_TEST_KEY"
    Pusher.secret = "MY_TEST_SECRET"
    require "pusher-fake/support/base"

    # Apply the pusher-fake fix
    Object.monkey_patch_pusher_fake!

    Hyperstack.configuration do |config|
      config.transport = :pusher
      config.channel_prefix = "synchromesh"
      config.opts = {app_id: Pusher.app_id, key: Pusher.key, secret: Pusher.secret, use_tls: false}.merge(PusherFake.configuration.web_options)
    end
  end

  before(:each) do
    # spec_helper resets the policy system after each test so we have to setup
    # before each test
    stub_const 'TestApplication', Class.new
    stub_const 'TestApplicationPolicy', Class.new
    TestApplicationPolicy.class_eval do
      always_allow_connection
      regulate_all_broadcasts { |policy| policy.send_all }
      allow_change(to: :all, on: [:create, :update, :destroy]) { true }
    end
    # size_window(:small, :portrait)
    FactoryBot.create(:test_model, test_attribute: 'I have been loaded', completed: true)
  end

  it 'will not use the defaultValue param until data is loaded - unit test' do
    mount_loadable_string_tester

    # initial value which is still loading
    expect(find('#uncontrolled-input').value).to eq('loading...')
    expect(find('#uncontrolled-checkbox')).not_to be_checked
    expect(find('#uncontrolled-select').value).to eq('loading...')
    expect(find('#uncontrolled-textarea').value).to eq('loading...')
    expect(find('#controlled-input').value).to eq('loading...')
    expect(find('#controlled-checkbox')).not_to be_checked
    expect(find('#controlled-select').value).to eq('loading...')
    expect(find('#controlled-textarea').value).to eq('loading...')

    # now we update so its loaded and the controlled and uncontrolled inputs will change
    evaluate_ruby("Tester.loadable_string.value = 'I have been loaded'")
    expect(find('#uncontrolled-input').value).to eq('I have been loaded')
    expect(find('#uncontrolled-checkbox')).to be_checked
    expect(find('#uncontrolled-select').value).to eq('I have been loaded')
    expect(find('#uncontrolled-textarea').value).to eq('I have been loaded')
    expect(find('#controlled-input').value).to eq('I have been loaded')
    expect(find('#controlled-checkbox')).to be_checked
    expect(find('#controlled-select').value).to eq('I have been loaded')
    expect(find('#controlled-textarea').value).to eq('I have been loaded')

    # now we update it again, but only the controlled inputs should change
    evaluate_ruby("Tester.loadable_string.value = 'another value'")
    expect(find('#uncontrolled-input').value).to eq('I have been loaded')
    expect(find('#uncontrolled-checkbox')).to be_checked
    expect(find('#uncontrolled-select').value).to eq('I have been loaded')
    expect(find('#uncontrolled-textarea').value).to eq('I have been loaded')
    expect(find('#controlled-input').value).to eq('another value')
    expect(find('#controlled-checkbox')).not_to be_checked
    expect(find('#controlled-select').value).to eq('another value')
    expect(find('#controlled-textarea').value).to eq('another value')

    # but if the user changes an input it will always change
    find('#uncontrolled-input').set 'I was set by the user'
    expect(find('#uncontrolled-input').value).to eq('I was set by the user')
    find('#uncontrolled-checkbox').set(false)
    expect(find('#uncontrolled-checkbox')).not_to be_checked
    find('#uncontrolled-select').find(:option, 'set by user').select_option
    expect(find('#uncontrolled-select').value).to eq('set by user')
    find('#uncontrolled-textarea').set 'I was set by the user'
    expect(find('#uncontrolled-textarea').value).to eq('I was set by the user')
    find('#controlled-input').set 'I was set by the user'
    expect(find('#controlled-input').value).to eq('I was set by the user')
    find('#controlled-checkbox').set(true)
    expect(find('#controlled-checkbox')).to be_checked
    expect_evaluate_ruby("Tester.loadable_string").to eq('I have been loaded')
    find('#controlled-select').find(:option, 'set by user').select_option
    expect(find('#controlled-select').value).to eq('set by user')
    find('#controlled-textarea').set 'text box set by the user'
    expect(find('#controlled-textarea').value).to eq('text box set by the user')
  end

  it "will properly update input tags when data is loaded or changed" do
    ReactiveRecord::Operations::Fetch.semaphore.synchronize do
      mount_input_tester
    end
    # #61: wait for the data to ARRIVE before reading the DOM.
    #
    # The gate that used to be here -- `not_to have_content('loading...', wait: 0)` --
    # was vacuous: 'loading...' only ever appears as an OPTION *value* attribute,
    # never as page text, and DummyValue#to_s returns ''. So nothing waited for the
    # fetch; `find` waited only for the ELEMENT, which exists immediately carrying the
    # placeholder, and `.value` was read once and compared with a non-retrying `eq`.
    # The example raced the fetch by construction -- that race is the whole of #61,
    # and it is why the failure looked like a flake with no correlation to Rails,
    # React, batch or runner load.
    #
    # have_field(..., with:) retries until Capybara's timeout, so it waits for the
    # VALUE rather than merely for the element to exist.
    expect(page).to have_field('uncontrolled-input', with: 'I have been loaded')
    expect(page).to have_field('uncontrolled-checkbox', checked: true)
    expect(page).to have_field('uncontrolled-select', with: 'I have been loaded')
    expect(page).to have_field('uncontrolled-textarea', with: 'I have been loaded')
    expect(page).to have_field('controlled-input', with: 'I have been loaded')
    expect(page).to have_field('controlled-checkbox', checked: true)
    expect(page).to have_field('controlled-select', with: 'I have been loaded')
    expect(page).to have_field('controlled-textarea', with: 'I have been loaded')

    TestModel.first.update(test_attribute: 'another value', completed: false)
    # Wait for the broadcast to land before asserting what did NOT change. Without
    # this the "unchanged" assertions below can pass simply because nothing has
    # arrived yet, which makes them prove nothing.
    expect(page).to have_field('controlled-input', with: 'another value')
    expect(find('#uncontrolled-input').value).to eq('I have been loaded')
    expect(find('#uncontrolled-checkbox')).to be_checked
    expect(find('#uncontrolled-select').value).to eq('I have been loaded')
    expect(find('#uncontrolled-textarea').value).to eq('I have been loaded')
    expect(find('#controlled-input').value).to eq('another value')
    expect(find('#controlled-checkbox')).not_to be_checked
    expect(find('#controlled-select').value).to eq('another value')
    expect(find('#controlled-textarea').value).to eq('another value')

    find('#uncontrolled-input').set 'I was set by the user', clear: :backspace
    expect(find('#uncontrolled-input').value).to eq('I was set by the user')

    find('#uncontrolled-checkbox').set(false)
    expect(find('#uncontrolled-checkbox')).not_to be_checked

    find('#uncontrolled-select').find(:option, 'set by user').select_option
    expect(find('#uncontrolled-select').value).to eq('set by user')

    find('#uncontrolled-textarea').set 'I was set by the user'
    expect(find('#uncontrolled-textarea').value).to eq('I was set by the user')

    find('#controlled-input').set 'I was also set by the user'
    expect(find('#controlled-input').value).to eq('I was also set by the user')
    evaluate_promise('TestModel.first.save')
    expect(TestModel.first.test_attribute).to eq('I was also set by the user')

    find('#controlled-checkbox').set(true)
    expect(find('#controlled-checkbox')).to be_checked
    evaluate_promise('TestModel.first.save')
    expect(TestModel.first.completed).to be_truthy

    find('#controlled-select').find(:option, 'set by user').select_option
    expect(find('#controlled-select').value).to eq('set by user')
    evaluate_promise('TestModel.first.save')
    expect(TestModel.first.test_attribute).to eq('set by user')

    find('#controlled-textarea').set 'text box set by the user'
    expect(find('#controlled-textarea').value).to eq('text box set by the user')
    evaluate_promise('TestModel.first.save')
    expect(TestModel.first.test_attribute).to eq('text box set by the user')
  end

  it "an uncontrolled tag keeps ignoring its prop after the user has typed in it" do
    # The guard the other two examples cannot state on their own.
    #
    # They check that an uncontrolled tag ignores a change that arrives while the tag
    # is untouched, and that the user can overwrite it. Neither checks the combination
    # -- a change arriving AFTER the user typed -- which is the case that actually
    # matters in an app: a record the user is editing gets updated by someone else,
    # and their half-typed edit must not be thrown away.
    #
    # To be straight about what this does and does not catch: it is contract coverage,
    # not a #62 regression test. Uncontrolled-ness comes from the element's dirty value
    # flag, and typing sets that flag by itself, so this example passes on the broken
    # build too. The assertion that fails without the #62 fix is the untouched-textarea
    # one in the two examples above (and, for this gem's own build,
    # hyper-component's spec/client_features/uncontrolled_textarea_spec.rb).
    mount_loadable_string_tester

    evaluate_ruby("Tester.loadable_string.value = 'I have been loaded'")
    expect(find('#uncontrolled-textarea').value).to eq('I have been loaded')

    find('#uncontrolled-input').set 'the user was typing'
    find('#uncontrolled-textarea').set 'the user was typing here too'
    find('#uncontrolled-select').find(:option, 'set by user').select_option

    evaluate_ruby("Tester.loadable_string.value = 'another value'")
    # the controlled tags prove the change really did arrive
    expect(page).to have_field('controlled-input', with: 'another value')
    expect(page).to have_field('controlled-textarea', with: 'another value')

    expect(find('#uncontrolled-input').value).to eq('the user was typing')
    expect(find('#uncontrolled-textarea').value).to eq('the user was typing here too')
    expect(find('#uncontrolled-select').value).to eq('set by user')
  end
end
