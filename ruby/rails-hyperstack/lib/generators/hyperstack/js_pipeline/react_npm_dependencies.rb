require 'json'

module Hyperstack
  # The npm dependency set the esbuild pipeline installs -- in ONE place. (#124)
  #
  # There are two consumers and they must not drift:
  #
  #   1. the install generator (js_pipeline/esbuild.rb), which writes the
  #      package.json of a real application;
  #   2. ruby/test_app_react_source.rb, which writes the package.json of every
  #      gem's spec/test_app when a cell selects HYPERSTACK_REACT_SOURCE=npm.
  #
  # Both used to carry their own copy of the same JSON *and* their own copy of
  # the '^19.0.0' React fallback. Nothing compared them, so the suite could have
  # been proving a dependency set we do not actually generate -- the same defect
  # #40 avoided for the four scaffolding templates by making them files with two
  # readers instead of two heredocs.
  #
  # == Why only react/react-dom are per-cell
  #
  # react and react-dom follow the cell (REACT_NPM_VERSION, set in
  # supported_versions.yml). The other four do NOT, and #124 is the record of
  # why -- each was pinned by assumption until it was actually checked:
  #
  # * react-router / react-router-dom are coupled to hyper-router's Ruby DSL, not
  #   to React. internal/router/helpers.rb defines `Switch` and `Redirect`, and
  #   internal/router/class_methods.rb feeds `create_browser_history` into
  #   `<Router history=>`; all three are the react-router 4/5 API. v6 removed
  #   Switch, Redirect and the `history` prop, and v7 additionally requires
  #   `react >= 18` / `react-dom >= 18` -- which would put the React 16 and 17
  #   cells out of range. So moving this pin is a hyper-router rewrite, not a
  #   version bump, and it cannot become a per-cell choice because the DSL is one
  #   DSL for the whole matrix.
  #
  #   5.3.4's own peer range is `react: >=15`, which spans every cell we run
  #   (16.14 -> 19.2). The caret is effectively exact: 5.3.4 is the last v5 ever
  #   published -- npm dist-tags it `classic` -- so `^5.3.4` can only ever resolve
  #   to 5.3.4.
  #
  # * history is not an independent choice at all. react-router 5.3.4 DEPENDS on
  #   history `^4.9.0`, so `^4.10.1` at the top level is what makes the resolver
  #   dedupe to a single copy. That is load-bearing rather than tidy: Opal reads
  #   `window.History` (react_runtime.js hoists it there) and
  #   React::Router::History.current.create_browser_history hands the result
  #   straight back to `<Router history=>`. Pin history 5 here and the app gets
  #   TWO histories -- a v5 on window and react-router's own nested v4 -- and the
  #   router is handed an object built by the wrong one. So this pin moves with
  #   the router pin or not at all. Like the router, `^4.10.1` is effectively
  #   exact: 4.10.1 is the last v4.
  #
  # * create-react-class has no peerDependencies and no react dependency, and
  #   15.7.0 is its final release (2020). It is not a legacy leftover to drop on
  #   React 19 either -- react_wrapper.rb's create_native_react_class builds EVERY
  #   Hyperstack component with it, so it is on the hot path of the whole
  #   framework on every cell.
  #
  # None of that is theory: the six npm cells run the entire suite, hyper-router
  # included, against React 19.2 with exactly these four, and they are green.
  # What was missing was the reason, which is what this file is.
  module ReactNpmDependencies
    # The React the esbuild bundles are built from when a cell does not select
    # one. Stated here ONCE (both consumers used to hard-code it) and checked
    # against supported_versions.yml by hyperstack-config's
    # react_npm_dependencies_spec.rb, so it cannot quietly fall behind the table
    # the way a second literal did.
    #
    # A caret, not a tilde: an unparameterised install should take the newest
    # patch of the series the matrix tests. The cells themselves pin `~19.2.0`
    # instead, because cell_contract_spec asserts the browser's
    # window.React.version against the cell's declared `react:`, and a caret
    # would float onto 19.3 and fail it. (#95)
    DEFAULT_REACT_NPM_VERSION = '^19.2.0'.freeze

    # Build-time only, and the one pin here that is not React-coupled: esbuild
    # compiles the bundles and never ships inside them.
    #
    # Note what the caret means on a 0.x version -- npm reads `^0.28.1` as
    # `>= 0.28.1, < 0.29.0`, so this is a pin to ONE minor series, not the
    # floating range it looks like. It moves by a deliberate bump or not at all,
    # which is why the line below records when it last moved and against what.
    #
    # LAST MOVED (#125): 0.23.1 (Aug 2024) -> 0.28.2, against React 19.2.8 --
    # the React every npm cell runs. Five minor series in one step, and it
    # changed essentially nothing: all three entrypoints still built, every
    # window/Opal.global global still set, the prerender bundle still loaded and
    # rendered in a real mini_racer isolate, and the minified output moved +216
    # bytes on react_runtime.js (+0.09%), +21 on react_server_runtime.js, -5 on
    # react_dom_server_runtime.js. react_runtime.js is 231,998 bytes, which is
    # still #107's 421 KB less the 189,490 #119 took out of it.
    #
    # == Why it moved: the audit finding, and the floor that clears it
    #
    # GHSA-67mh-4wv8-2f99 (medium) covers esbuild <= 0.24.2, so `yarn audit` in
    # a freshly generated app reported it out of the box. It is a DEVELOPMENT
    # SERVER flaw -- any website can issue requests to `esbuild serve` and read
    # the response -- and esbuild.config.js calls `require('esbuild').build()`
    # and never `serve()`, so nothing here was ever exposed to it. The finding
    # was noise; it was noise every generated app inherited, on a dependency the
    # user did not choose and could not easily explain away.
    #
    # The floor is 0.28.1 rather than 0.28.0, and that digit is the point.
    # esbuild has a SECOND advisory, GHSA-g7r4-m6w7-qqqr (low), covering
    # `>= 0.27.3, < 0.28.1`. A caret is a RANGE, so `^0.28.0` would still admit
    # 0.28.0 and hand a fresh `yarn install` a version inside it -- trading one
    # audit finding for another. `^0.28.1` puts the whole admissible range above
    # both. It is the RANGE that has to be clean, not just the version that
    # happens to resolve today, and react_npm_dependencies_spec.rb asserts that
    # -- both advisory windows written out, so a later bump back into either one
    # fails rather than ships.
    #
    # What an upgrade can no longer break silently: #120 pinned target, minify
    # and sourcemap explicitly, so the browser baseline is stated by the config
    # rather than inherited from whichever esbuild is installed. That is what
    # made this bump checkable instead of a leap.
    ESBUILD_VERSION = '^0.28.1'.freeze

    # Pinned by hyper-router's DSL rather than by React -- see the module comment.
    REACT_ROUTER_VERSION = '^5.3.4'.freeze
    # Pinned by react-router's own `history ^4.9.0` dependency, so the app and the
    # router share ONE history module. Moves with REACT_ROUTER_VERSION.
    HISTORY_VERSION = '^4.10.1'.freeze
    # The class factory every Hyperstack component is built with. Final release.
    CREATE_REACT_CLASS_VERSION = '^15.7.0'.freeze

    module_function

    # The npm React, selected per cell exactly as REACT_RAILS_VERSION selects the
    # sprockets/react-rails one. (#51)
    def react_version
      selected = ENV['REACT_NPM_VERSION']
      # Blank means unset, the rule Hyperstack.version_selector already applies to
      # the Ruby selectors: an exported-but-empty variable is a cell that left the
      # key out, not a request for the requirement ''. Here it would have reached
      # npm as `"react": ""`, which yarn resolves to the LATEST react -- silently
      # taking the cell off the React axis it claims. (#78)
      selected.nil? || selected.strip.empty? ? DEFAULT_REACT_NPM_VERSION : selected
    end

    def dependencies
      {
        'create-react-class' => CREATE_REACT_CLASS_VERSION,
        'history' => HISTORY_VERSION,
        'react' => react_version,
        'react-dom' => react_version,
        'react-router' => REACT_ROUTER_VERSION,
        'react-router-dom' => REACT_ROUTER_VERSION
      }
    end

    def dev_dependencies
      { 'esbuild' => ESBUILD_VERSION }
    end

    # The whole file, so the two consumers cannot differ in key order or
    # whitespace either. `build` is the script jsbundling-rails runs on
    # assets:precompile, and the same one a test_app invokes by hand.
    def package_json(name:)
      JSON.pretty_generate(
        'name' => name,
        'private' => true,
        'scripts' => { 'build' => 'node esbuild.config.js' },
        'dependencies' => dependencies,
        'devDependencies' => dev_dependencies
      ) + "\n"
    end
  end
end
