require 'spec_helper'

# Regression coverage for the React 18 mount rewrite (#18): createRoot mount +
# unmount, the per-container root (re-render reuse), and the flushSync-backed
# synchronous force_update!/set_state! contract. Feature-detected, so these also
# pass on React 17 (legacy ReactDOM.render / unmountComponentAtNode).
#
# Salvaged from the retired rails-7 / rails-8.0 / rails-8.1 branch lines, which
# is the only place it ever lived -- edge ships the createRoot code with no spec
# covering it. Those lines ran ONE cell each, so every example below has only
# ever been green on React 18. edge runs it on all ten cells, React 16 through
# 19, which is why the root-handle example is gated: `__hyperstackReactRoot` is
# set only on react_api.rb's `typeof ReactDOM.createRoot === 'function'` branch,
# so on the React 16/17 cells it is legitimately absent. The rest are written
# against behaviour both paths share and are expected to hold everywhere -- but
# that is a prediction until a full-matrix run says otherwise.
describe 'React 18 mount API', js: true do
  it 'mounts and renders a component (createRoot)' do
    mount 'Foo' do
      class Foo
        include Hyperstack::Component
        render(DIV, class: :greeting) { 'hello from react 18' }
      end
    end
    expect(page).to have_css('.greeting')
    expect(page).to have_content('hello from react 18')
  end

  it 'mounts without any console errors (warning-free createRoot)' do
    mount 'Foo' do
      class Foo
        include Hyperstack::Component
        render(DIV) { 'no warnings please' }
      end
    end
    expect(page).to have_content('no warnings please')
    errors = page.driver.browser.logs.get(:browser)
      .reject { |e| e.to_s.include?('Deprecated feature') }
      .reject { |e| e.to_s.include?('Object freezing is not supported by Opal') }
      .reject { |e| e.to_s =~ /require '[^']*'/ }
      .reject { |e| e.to_s.include?('Download the React DevTools') }
      .reject { |e| e.to_s.include?('%c') }
      .select { |e| e.level == 'SEVERE' }
    expect(errors.map(&:message)).to eq([])
  end

  it 'force_update! re-renders synchronously (flushSync)' do
    mount 'Foo' do
      class Foo
        include Hyperstack::Component
        class << self; attr_accessor :render_count, :instance; end
        before_mount { Foo.render_count = 0; Foo.instance = self }
        render(DIV) { Foo.render_count += 1; "rendered #{Foo.render_count}" }
      end
    end
    # Read ONCE, not expect_evaluate_ruby. Two reasons, both #83: the block
    # mutates the very count it asserts, so a mismatching first read would make
    # every retry diverge instead of converge; and this is a SYNCHRONICITY
    # assertion, so polling would let a merely-eventual re-render satisfy the
    # matcher that exists to prove the re-render was immediate.
    expect(evaluate_ruby do
      Foo.instance.force_update!
      Foo.render_count
    end).to eq(2)
  end

  it 'set_state! re-renders synchronously (flushSync)' do
    mount 'Foo' do
      class Foo
        include Hyperstack::Component
        class << self; attr_accessor :render_count, :instance; end
        before_mount { Foo.render_count = 0; Foo.instance = self }
        render(DIV) { Foo.render_count += 1; "rendered #{Foo.render_count}" }
      end
    end
    # Read once, for the reasons on the example above.
    #
    # The expected count differs by React major, and that difference IS the
    # contract rather than a wart to paper over. set_state! is `setState` and
    # then `forceUpdate` (instance_methods.rb):
    #
    #   React 18+   setState is batched, and the flushSync around forceUpdate
    #               flushes both together -- ONE re-render          -> 2
    #   React <=17  legacy mode with no flushSync, and this runs outside React's
    #               event system (execute_script), so setState is unbatched and
    #               renders immediately; forceUpdate then renders again
    #               -- TWO re-renders                               -> 3
    #
    # Both are synchronous, which is what this example is about; only the
    # coalescing differs. Asserting a flat 2 was correct on the single React 18
    # cell the retired branch lines ran and wrong on React 16/17 -- and because
    # the old expect_evaluate_ruby polled, the mismatch showed up as
    # `expected 2, got 107`, a retry counter, rather than as the real answer 3.
    expected_renders = react_version_major >= 18 ? 2 : 3
    expect(evaluate_ruby do
      Foo.instance.set_state!(x: 1) # setState + forceUpdate
      Foo.render_count
    end).to eq(expected_renders)
  end

  it 'dom_node resolves via refs without the findDOMNode deprecation warning (#18)' do
    mount 'Foo' do
      class Foo
        include Hyperstack::Component
        class << self; attr_accessor :instance; end
        after_mount { Foo.instance = self }
        render(DIV, class: :with_node) { 'has a dom node' }
      end
    end
    expect(page).to have_css('.with_node')
    # dom_node returns the mounted host element via the ref chain (not findDOMNode)
    expect_evaluate_ruby('Foo.instance.dom_node.JS[:className]').to eq('with_node')
    finddomnode = page.driver.browser.logs.get(:browser)
      .select { |e| e.level == 'SEVERE' }
      .map(&:message)
      .select { |m| m.include?('findDOMNode') }
    expect(finddomnode).to eq([])
  end

  it 'foreign-component dom_node resolves via the fiber walk, not findDOMNode (#18)' do
    mount 'Wrapper' do
      Opal::Raw.call(:eval,
        <<-JSCODE
          window.AForeignComponent = class extends React.Component {
            render() { return React.createElement('div', { className: 'foreign-node' }, 'foreign content'); }
          }
        JSCODE
      )
      class Foreign < Hyperloop::Component
        imports 'AForeignComponent'
      end
      class Wrapper < HyperComponent
        # dom_node on a foreign (non-Hyperstack) class component: no ref substitute,
        # so it walks the component's React fiber to the first host node instead of
        # calling the deprecated findDOMNode.
        after_mount { raise 'wrong dom_node' unless @foreign.dom_node.JS[:className] == 'foreign-node' }
        render { @foreign = Foreign() }
      end
    end
    expect(page).to have_css('.foreign-node')
    expect(page).to have_content('foreign content')
    finddomnode = page.driver.browser.logs.get(:browser)
      .select { |e| e.level == 'SEVERE' }
      .map(&:message)
      .select { |m| m.include?('findDOMNode') }
    expect(finddomnode).to eq([])
  end

  it 'force_update! inside a lifecycle does not trigger a flushSync warning (#18)' do
    mount 'Foo' do
      class Foo
        include Hyperstack::Component
        class << self; attr_accessor :render_count; end
        before_mount { Foo.render_count = 0 }
        # after_mount runs in React's commit phase: flushSync must be skipped here
        after_mount { force_update! }
        render(DIV, class: :lifecycle) { Foo.render_count += 1; "render #{Foo.render_count}" }
      end
    end
    expect(page).to have_css('.lifecycle')
    expect(page).to have_content('render 2') # the after_mount force_update! re-rendered
    flush = page.driver.browser.logs.get(:browser)
      .select { |e| e.level == 'SEVERE' }
      .map(&:message)
      .select { |m| m.include?('flushSync') }
    expect(flush).to eq([])
  end

  it 'reuses one root for re-renders and unmounts via root.unmount' do
    # React 18+ only: react_api.rb creates and stores __hyperstackReactRoot on the
    # createRoot branch. React 16/17 take the legacy ReactDOM.render path, where no
    # root handle exists and there is nothing to reuse or to unmount through.
    skip 'createRoot path is React 18+' if react_version_major < 18
    # Read once (#83): the block appends a container to document.body and mounts
    # into it, so each retry would leak another one, and the whole render /
    # re-render / unmount sequence completes inside a single evaluation -- there
    # is no later-arriving value for polling to wait for.
    expect(evaluate_ruby do
      class Foo
        include Hyperstack::Component
        param :label
        render(DIV, class: :reusable) { @Label }
      end
      container = `document.createElement('div')`
      `document.body.appendChild(container)`
      render_el = ->(label) { Hyperstack::Component::ReactAPI.render(
        Hyperstack::Component::ReactAPI.create_element(Foo, label: label), container) }
      render_el.call('first')
      render_el.call('second') # re-render: must reuse the same createRoot
      first_root = `container.__hyperstackReactRoot`
      Hyperstack::Component::ReactAPI.unmount_component_at_node(container)
      # after unmount the root handle is cleared and the container is empty
      [`!!first_root`, `container.__hyperstackReactRoot === undefined`, `container.innerHTML === ''`]
    end).to eq([true, true, true])
  end
end
