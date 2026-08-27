require 'spec_helper'

# The companion to uncontrolled_components_spec.rb, which only checks that an uncontrolled
# tag picks its INITIAL value up. This checks the other half of the contract -- that it
# then IGNORES the prop -- which is where <textarea> was wrong (#62).
#
# It belongs here rather than only in hyper-model's default_value_spec because the fix
# is in ReactWrapper.convert_props, and nothing in this gem's own suite would otherwise
# notice it being lost.
#
# The default value is deliberately an OBJECT rather than a string literal. React
# decides whether to set a textarea's dirty value flag by comparing the text content it
# rendered against `_wrapperState.initialValue` with `===`, and it stores that one
# uncoerced -- so the check only survives a javascript string PRIMITIVE. A ruby string
# literal happens to be one, which is why a spec written with `defaultValue: 'x'` passes
# even on the broken build and proves nothing. Anything with a `to_s` -- a value object,
# an observable, hyper-model's DummyValue -- is an object, and that is the real case.
describe 'uncontrolled components ignore later prop changes', js: true do
  before(:each) do
    before_mount do
      class Text
        def initialize(s)
          @s = s
        end
        def to_s
          @s
        end
      end
      class Store
        include Hyperstack::State::Observable
        class << self
          state_accessor :text
        end
      end
      class TagTester < HyperComponent
        render(DIV) do
          INPUT(id: :uncontrolled_input, defaultValue: Store.text)
          TEXTAREA(id: :uncontrolled_textarea, defaultValue: Store.text)
          SELECT(id: :uncontrolled_select, defaultValue: Store.text) do
            OPTION(value: 'first value') { 'first value' }
            OPTION(value: 'second value') { 'second value' }
          end
          # the controlled tag is the control: it proves the change really reached the
          # component, so a passing "did not change" assertion cannot be vacuous.
          TEXTAREA(id: :controlled_textarea, value: Store.text)
          .on(:change) { |evt| Store.text = Text.new(evt.target.value) }
        end
      end
      Store.text = Text.new('first value')
    end
  end

  it 'an uncontrolled tag takes its first value and then ignores the prop' do
    mount 'TagTester'

    expect(find('#uncontrolled_input').value).to eq('first value')
    expect(find('#uncontrolled_textarea').value).to eq('first value')
    expect(find('#uncontrolled_select').value).to eq('first value')

    evaluate_ruby("Store.text = Text.new('second value')")
    expect(page).to have_field('controlled_textarea', with: 'second value')

    expect(find('#uncontrolled_input').value).to eq('first value')
    expect(find('#uncontrolled_textarea').value).to eq('first value')
    expect(find('#uncontrolled_select').value).to eq('first value')
  end

  it 'an uncontrolled tag does not overwrite what the user typed' do
    mount 'TagTester'

    find('#uncontrolled_input').set 'the user was typing'
    find('#uncontrolled_textarea').set 'the user was typing here too'

    evaluate_ruby("Store.text = Text.new('second value')")
    expect(page).to have_field('controlled_textarea', with: 'second value')

    expect(find('#uncontrolled_input').value).to eq('the user was typing')
    expect(find('#uncontrolled_textarea').value).to eq('the user was typing here too')
  end
end
