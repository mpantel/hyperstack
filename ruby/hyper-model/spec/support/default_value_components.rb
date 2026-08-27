# The client-side components shared by spec/batch4/default_value_spec.rb.
#
# They live here rather than inline in the example because more than one example
# needs the same ~60-line tag set, and a copy per example is exactly how
# default_value_textarea_spec.rb came to exist -- a 248-line duplicate carrying two
# assertions, which then drifted from the file it was copied from (#62).
#
# hyper-spec ships a mount block to the browser by reading its SOURCE (see
# HyperSpec::Internal::ComponentMount#add_block_with_helpers), so a block written in
# this file behaves exactly as if it had been written in the example itself.
module DefaultValueComponents
  # Every tag in both components comes in an uncontrolled and a controlled flavour, and
  # they are asserted against each other. That pairing is the point: "uncontrolled"
  # means the element takes its value ONCE and then ignores the prop, so the only way
  # to tell a working uncontrolled tag from a broken one is a controlled tag next to it
  # that does keep tracking.

  # Backed by a plain observable, so the loading -> loaded transition is driven by hand
  # from the spec (`Tester.loadable_string.value = ...`) rather than by a real fetch.
  # (define_method, not def: ruby forbids a class definition inside a method BODY,
  # but allows one inside a block -- and the components have to be class definitions.)
  define_method(:mount_loadable_string_tester) do
    mount 'Tester' do
      class LoadableString
        include Hyperstack::State::Observable
        def initialize(s)
          @s = s
        end
        observer :to_s do
          if @loaded
            @s
          else
            Hyperstack::Internal::Component::RenderingContext.waiting_on_resources = true
            "loading..."
          end
        end
        observer :loading? do
          !@loaded
        end
        def value
          self
        end
        mutator :value= do |x|
          @loaded = true
          @s = x
        end
      end
      class Tester < HyperComponent
        include Hyperstack::Component::IsomorphicHelpers
        def self.loadable_string
          @loadable_string
        end
        before_first_mount do
          @loadable_string = LoadableString.new(self)
        end
        render(DIV) do
          INPUT(id: 'uncontrolled-input', defaultValue: Tester.loadable_string.value)
          INPUT(id: 'uncontrolled-checkbox', type: :checkbox, defaultChecked: -> () { Tester.loadable_string.to_s == 'I have been loaded' })
          SELECT(id: 'uncontrolled-select', defaultValue: Tester.loadable_string.value) do
            OPTION(value: 'loading...') { "loading..." }
            OPTION(value: 'I have been loaded') { "I have been loaded" }
            OPTION(value: 'another value') { "another value" }
            OPTION(value: 'set by user') { "set by user" }
          end
          TEXTAREA(id: 'uncontrolled-textarea', defaultValue: Tester.loadable_string.value)

          INPUT(id: 'controlled-input', value: Tester.loadable_string.value, valuex: Tester.loadable_string.value)
          .on(:change) { |evt| Tester.loadable_string.value = evt.target.value }
          INPUT(id: 'controlled-checkbox', type: :checkbox, checked: Tester.loadable_string.to_s == 'I have been loaded')
          .on(:change) { |evt| Tester.loadable_string.value = evt.target.checked ? 'I have been loaded' : 'The user clicked off the checkbox' }
          SELECT(id: 'controlled-select', value: Tester.loadable_string.value) do
            OPTION(value: 'loading...') { "loading..." }
            OPTION(value: 'I have been loaded') { "I have been loaded" }
            OPTION(value: 'another value') { "another value" }
            OPTION(value: 'set by user') { "set by user" }
          end
          .on(:change) { |evt| Tester.loadable_string.value = evt.target.value }
          TEXTAREA(id: 'controlled-textarea', value: Tester.loadable_string.value)
          .on(:change) { |evt| Tester.loadable_string.value = evt.target.value }
        end
      end
    end
  end

  # The same tag set, backed by a real reactive record, so the loading -> loaded
  # transition is driven by an actual fetch. Callers hold
  # ReactiveRecord::Operations::Fetch.semaphore while they want the data to stay
  # unloaded, and mount with no_wait so the example keeps running while it is held.
  define_method(:mount_input_tester) do
    mount 'InputTester', {}, no_wait: true do
      class InputTester < HyperComponent
        before_mount do
          @test_model = TestModel.first
        end
        render(DIV) do
          INPUT(id: 'uncontrolled-input', defaultValue: @test_model.test_attribute)
          INPUT(id: 'uncontrolled-checkbox', type: :checkbox, defaultChecked: @test_model.completed)
          SELECT(id: 'uncontrolled-select', defaultValue: @test_model.test_attribute) do
            OPTION(value: 'loading...') { "" }
            OPTION(value: 'I have been loaded') { "I have been loaded" }
            OPTION(value: 'another value') { "another value" }
            OPTION(value: 'set by user') { "set by user" }
          end
          TEXTAREA(id: 'uncontrolled-textarea', defaultValue: @test_model.test_attribute)

          INPUT(id: 'controlled-input', value: @test_model.test_attribute)
          .on(:change) { |evt| @test_model.test_attribute = evt.target.value }
          INPUT(id: 'controlled-checkbox', type: :checkbox, checked: @test_model.completed)
          .on(:change) { |evt| @test_model.completed = evt.target.checked }
          SELECT(id: 'controlled-select', value: @test_model.test_attribute) do
            OPTION(value: 'loading...') { "" }
            OPTION(value: 'I have been loaded') { "I have been loaded" }
            OPTION(value: 'another value') { "another value" }
            OPTION(value: 'set by user') { "set by user" }
          end
          .on(:change) { |evt| @test_model.test_attribute = evt.target.value }
          TEXTAREA(id: 'controlled-textarea', value: @test_model.test_attribute)
          .on(:change) { |evt| @test_model.test_attribute = evt.target.value }
        end
      end
    end
  end
end

RSpec.configure { |config| config.include DefaultValueComponents }
