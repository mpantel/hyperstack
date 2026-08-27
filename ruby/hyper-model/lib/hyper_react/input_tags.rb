# Special handling of input tags so they ignore defaultValue (and defaultChecked) values while loading.
#
# React applies defaultValue/defaultChecked to an uncontrolled element at MOUNT and never again,
# but the whole premise of hyper-model is "render now, the data arrives later": the first render
# gets a DummyValue, and the real value only turns up once the fetch lands.  Something therefore
# has to carry that late value into an element that react has already finished with.
#
# It used to be a react `key` derived from the value's `loading?` state.  When the key flipped
# true -> false react threw the element away and mounted a fresh one, and the fresh one mounted
# carrying the loaded value.  It worked, and it destroyed the DOM node to do it -- so anything the
# user had typed into the field while the data was still on its way went with it (#72).  That is
# the normal case, not an exotic one: any field the user reaches before the fetch lands is exposed.
#
# So instead we keep the element and write the loaded value into it ourselves, exactly once, on the
# loading -> loaded transition, via a ref (see UncontrolledDefault below).
#
# To handle cases where defaultValue (or defaultChecked) is an expression, a proc (or lambda) can be
# provided for the default value.  The proc will be called, and if it raises the waiting_on_resources
# flag then we know that within that expression there is a value still being loaded, and the element
# is treated as loading accordingly.

module Hyperstack
  module Internal
    module Component
      module Tags
        # Carries a late-arriving defaultValue/defaultChecked into an element react has already
        # mounted, without disturbing what the user has done to it in the meantime (#72).
        #
        # The ref fires on every render (a new proc each time, so react re-attaches it), and does
        # one of two things:
        #
        #   while loading  -- mark the node as owing an update, and remember what the placeholder
        #                     render left in the DOM, so we can tell later whether the user typed
        #                     over it.
        #   once loaded    -- if the node still holds the placeholder, or already holds the target
        #                     (react itself sometimes gets there first, see below), assign the
        #                     target.  Then stop: this element is uncontrolled from here on.
        #
        # Applying exactly once is what keeps the element uncontrolled -- later changes to the same
        # prop must NOT reach the DOM, which is what default_value_spec asserts a few lines on with
        # "only the controlled inputs should change" (#62).  An element that mounts with an
        # already-loaded value never owes an update at all, so that path is untouched.
        #
        # The assignment is not redundant when the node already holds the target value.  Whether an
        # uncontrolled element ignores its prop is decided by its DIRTY VALUE FLAG (dirty checkedness
        # flag for a checkbox), and react only sets that at mount as a side effect of assigning a
        # value that differs from what is already in the node.  Mount with the empty placeholder a
        # DummyValue renders as and nothing differs, so the flag stays clear -- and while it is
        # clear the DOM value follows `node.defaultValue`, which react rewrites on EVERY render.
        # That is how the loaded value reaches an untouched <input> or <textarea> without us, and it
        # is equally how the value after it would.  Assigning through the IDL property sets the flag
        # (the HTML spec says the setter always does, whatever the value), which closes the element
        # for good.  A <select> has no such flag; react simply ignores defaultValue on update, so
        # for it the assignment is the only thing that applies the value at all.
        #
        # The bookkeeping lives ON THE NODE, so it is destroyed with the element.  An earlier attempt
        # (ae96a67f, reverted hours later in 3d3f3c80) kept it in a window-level hash that outlived
        # the element and leaked across specs.
        #
        # Known limit: "the user typed" is inferred by comparing the node against the placeholder, so
        # a user who types and then deletes back to exactly the placeholder is indistinguishable from
        # one who never touched the field, and gets the loaded value.  Reading the dirty value flag
        # itself would settle it, but the DOM does not expose it.
        module UncontrolledDefault
          def self.install(opts, default_key, value, loading)
            return unless default_key

            checked = default_key == :defaultChecked
            prop    = checked ? 'checked' : 'value'
            # While loading there is no string to be had, and asking a DummyValue for one notifies
            # the loading machinery -- precisely what this file goes out of its way not to do.
            # `'' + x` rather than plain `to_s`: to_s can hand back a BOXED opal String, which is
            # `typeof` 'object' and so never `===` anything the DOM gives back (#62).
            target = if loading
                       nil
                     elsif checked
                       !!value
                     else
                       `'' + #{value.to_s}`
                     end

            previous_ref = opts[:ref]
            opts[:ref] = lambda do |node|
              apply(node, prop, loading, target)
              previous_ref.call(node) if previous_ref
            end
          end

          # Client side only -- the whole file is (see hyper-model.rb), which is what makes the
          # `%x{}` below safe: under MRI it would be a shell command.
          def self.apply(node, prop, loading, target)
            %x{
              if (node && node.nodeType === 1) {
                if (#{loading}) {
                  node.__hyperstack_default_pending = true;
                  if (node.__hyperstack_default_placeholder === undefined) {
                    node.__hyperstack_default_placeholder = node[prop];
                  }
                } else if (node.__hyperstack_default_pending) {
                  node.__hyperstack_default_pending = false;
                  if (node[prop] === node.__hyperstack_default_placeholder ||
                      node[prop] === target) {
                    node[prop] = target;
                  }
                }
              }
            }
            nil
          end
        end

        %i[INPUT SELECT TEXTAREA].each do |component|
          remove_method component
          send(:remove_const, component)
          tag = component.downcase
          klass = Class.new do
            include Hyperstack::Component
            collect_other_params_as :opts
            render do
              opts = props.dup  # should be opts = params.opts.dup but requires next release candiate of hyper-react
              default_key = if opts.key?(:defaultValue)
                              :defaultValue
                            elsif opts.key?(:defaultChecked)
                              :defaultChecked
                            end
              default_value = default_key && opts[default_key]
              if default_value.respond_to? :call
                begin
                  saved_waiting_on_resources = Hyperstack::Internal::Component::RenderingContext.waiting_on_resources
                  Hyperstack::Internal::Component::RenderingContext.waiting_on_resources = false
                  default_value = default_value.call
                  loading = Hyperstack::Internal::Component::RenderingContext.waiting_on_resources
                  opts[default_key] = default_value
                ensure
                  Hyperstack::Internal::Component::RenderingContext.waiting_on_resources = !!saved_waiting_on_resources
                end
              else
                loading = !!(default_key && default_value.loading?)
              end
              Hyperstack::Internal::Component::Tags::UncontrolledDefault.install(opts, default_key, default_value, loading)
              opts[:value] = opts[:value].to_s if opts.key? :value  # this may not be needed
              Hyperstack::Internal::Component::RenderingContext.render(tag, opts) { children.each(&:render) }
            end
          end

          Object.const_set component, klass
        end
      end
    end
  end
end
