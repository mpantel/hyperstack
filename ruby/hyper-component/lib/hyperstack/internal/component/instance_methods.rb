require "hyperstack/component/children"

module Hyperstack
  module Internal
    module Component
      module InstanceMethods
        def children
          Hyperstack::Component::Children.new(`#{@__hyperstack_component_native}.props.children`)
        end

        def params
          if [:hyperstack, :accessors].include? @__hyperstack_component_params_wrapper.param_accessor_style
            raise "params are now directly accessible via instance variables.\n"\
                  '  to access the legacy behavior add `param_accessor_style = :legacy` '\
                    "to your component class\n"\
                  '  to access both behaviors add `param_accessor_style = :both` '\
                    'to your component class'
          end
          @__hyperstack_component_params_wrapper
        end

        def props
          Hyperstack::Internal::Component.native_to_hash(`#{@__hyperstack_component_native}.props`)
        end

        def dom_node
          # React 18 (#18): resolve the DOM node by walking the component's own React
          # fiber (`_reactInternals`) to its first host node. This is robust whenever the
          # component is mounted — independent of ref-callback timing (the earlier
          # ref-chain approach raised "instance not mounted yet" in transient states like
          # while-loading) — and avoids the deprecated findDOMNode console.error. Falls
          # back to findDOMNode if the fiber shape is unknown / pre-18.
          %x{
            var native = #{self}.__hyperstack_component_native;
            var fiber = native._reactInternals || native._reactInternalFiber;
            var walk = function(node) {
              for (var n = node; n; n = n.sibling) {
                if (n.stateNode && n.stateNode.nodeType) { return n.stateNode; }
                var deep = n.child ? walk(n.child) : null;
                if (deep) { return deep; }
              }
              return null;
            };
            var found = fiber ? walk(fiber.child) : null;
            if (found) { return found; }
            return (typeof ReactDOM !== 'undefined' && ReactDOM.findDOMNode) ? ReactDOM.findDOMNode(native) : null;
          }
        end

        def jq_node
          ::Element[dom_node]
        end

        def mounted?
          `(#{self}.__hyperstack_component_is_mounted === undefined) ? false : #{self}.__hyperstack_component_is_mounted`
        end

        def pluralize(count, singular, plural = nil)
          word = if (count == 1 || count =~ /^1(\.0+)?$/)
            singular
          else
            plural || singular.pluralize
          end

          "#{count || 0} #{word}"
        end

        # React 18 (#18): forceUpdate/setState are async (automatic batching), so a
        # synchronous read after force_update! would see the pre-render value.
        # flushSync (when present) restores Hyperstack's synchronous-update contract.
        def force_update!
          %x{
            var native = #{self}.__hyperstack_component_native;
            // React 18 (#18): flushSync gives the synchronous-update contract, but React
            // warns and refuses to flush when called while it is already rendering or
            // committing (force_update! from a lifecycle like after_mount, or mutate during
            // render). There, fall back to a plain forceUpdate (applied in the current
            // cycle); use flushSync only when called from outside React (e.g. event handlers).
            if (typeof ReactDOM !== 'undefined' && ReactDOM.flushSync && !(Opal.global.__hyperstack_in_react > 0)) {
              ReactDOM.flushSync(function(){ native.forceUpdate(); });
            } else {
              native.forceUpdate();
            }
          }
          self
        end

        def set_state(state, &block)
          set_or_replace_state_or_prop(state, 'setState', &block)
        end

        def set_state!(state, &block)
          set_or_replace_state_or_prop(state, 'setState', &block)
          %x{
            var native = #{self}.__hyperstack_component_native;
            // React 18 (#18): flushSync gives the synchronous-update contract, but React
            // warns and refuses to flush when called while it is already rendering or
            // committing (force_update! from a lifecycle like after_mount, or mutate during
            // render). There, fall back to a plain forceUpdate (applied in the current
            // cycle); use flushSync only when called from outside React (e.g. event handlers).
            if (typeof ReactDOM !== 'undefined' && ReactDOM.flushSync && !(Opal.global.__hyperstack_in_react > 0)) {
              ReactDOM.flushSync(function(){ native.forceUpdate(); });
            } else {
              native.forceUpdate();
            }
          }
        end

        # https://github.com/hyperstack-org/hyperstack/issues/363
        def accepts?(aka)
          self.props[self.class.accepts_list[aka]]
        end

        private

        # can be overriden by the Router include
        def __hyperstack_router_wrapper(&block)
          ->() { instance_eval(&block) }
        end

        # can be overriden by including WhileLoading include
        def __hyperstack_component_rescue_wrapper(child)
          if self.class.callbacks?(:__hyperstack_component_rescue_hook)
            Hyperstack::Internal::Component::RescueWrapper(child: self, children_elements: child)
          else
            child.call
          end
        end

        def __hyperstack_component_select_wrappers(&block)
          RescueWrapper.after_error_args = nil
          __hyperstack_component_run_post_render_hooks(
            __hyperstack_component_rescue_wrapper(
              __hyperstack_router_wrapper(&block)
            )
          )
        end

        def set_or_replace_state_or_prop(state_or_prop, method, &block)
          raise "No native ReactComponent associated" unless @__hyperstack_component_native
          `var state_prop_n = #{state_or_prop.shallow_to_n}`
          # the state object is initalized when the ruby component is instantiated
          # this is detected by self.__hyperstack_component_native.__opalInstanceInitializedState
          # which is set in the native component constructor in ReactWrapper
          # the setState update callback is not called when initalizing initial state
          if block
            %x{
              if (#{@__hyperstack_component_native}.__opalInstanceInitializedState === true) {
                #{@__hyperstack_component_native}[method](state_prop_n, function(){
                  block.$call();
                });
              } else {
                for (var sp in state_prop_n) {
                  if (state_prop_n.hasOwnProperty(sp)) {
                    #{@__hyperstack_component_native}.state[sp] = state_prop_n[sp];
                  }
                }
              }
            }
          else
            %x{
              if (#{@__hyperstack_component_native}.__opalInstanceInitializedState === true) {
                #{@__hyperstack_component_native}[method](state_prop_n);
              } else {
                for (var sp in state_prop_n) {
                  if (state_prop_n.hasOwnProperty(sp)) {
                    #{@__hyperstack_component_native}.state[sp] = state_prop_n[sp];
                  }
                }
              }
            }
          end
        end
      end
    end
  end
end
