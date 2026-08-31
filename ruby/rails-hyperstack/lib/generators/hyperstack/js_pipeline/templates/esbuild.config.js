// esbuild build (#19). IIFE format (not esm) so the bundles set the window /
// Opal.global React globals immediately. Output -> app/assets/builds (served by
// sprockets). jsbundling-rails runs this via the package.json "build" script.

// One signal for both `define` and `minify`, so a development build is
// development in both senses. Defaults to production: this bundle is served to
// every page of the app (the layout loads it with its own include tag, #108),
// so the default has to be what ships, not what debugs. (#107)
const nodeEnv = process.env.NODE_ENV || 'production';

require('esbuild').build({
  entryPoints: [
    'app/javascript/react_runtime.js',        // client: window globals
    'app/javascript/react_server_runtime.js', // prerender (V8): Opal.global globals
    // Opt-in, NOT required by application.js unless the app asks for it (#119).
    // Built unconditionally so it is on disk the moment someone adds
    // `//= require react_dom_server_runtime`; building it costs disk, not
    // bandwidth, since sprockets only serves what is required.
    'app/javascript/react_dom_server_runtime.js', // client-side ReactDOMServer
  ],
  bundle: true,
  outdir: 'app/assets/builds',
  // Declare the browser baseline instead of inheriting it (#120). Unset, esbuild
  // defaults to `esnext` and downlevels NOTHING, so "which browsers does this app
  // support?" was answered by whichever esbuild version happened to be in
  // package.json -- and an esbuild upgrade could move it silently.
  //
  // es2020 is Chrome 80 / Safari 13.1 / Firefox 72, all 2020 or earlier, and
  // comfortably below what React 18/19 already require, so pinning it costs
  // nothing today. It is a floor, not a ceiling: an app that needs a different
  // baseline edits this file, which is generated into the app and owned by it.
  target: ['es2020'],
  define: { 'process.env.NODE_ENV': JSON.stringify(nodeEnv) },
  // Without this the bundle shipped unminified -- 1.2 MB, which esbuild itself
  // flags. `define` above already selects React's production code, so this is
  // purely identifiers/whitespace/comments and changes no behaviour: React was
  // never running its development build here. Sprockets does not compress
  // JavaScript by default and nothing sets config.assets.js_compressor, so
  // whatever esbuild emits is what the browser gets. (#107)
  //
  // NODE_ENV=development skips it, for anyone who needs to read the bundle.
  minify: nodeEnv === 'production',
  // Same signal, pointing the same way: a development build is minify-off and
  // mapped-on, a production build is minify-on and mapped-off. (#120)
  //
  // Production maps are deliberately NOT emitted. They only earn their place
  // when something CONSUMES them -- an error tracker ingesting maps privately to
  // symbolicate traces. A generated app has no such integration, so publishing
  // them would just serve the original module structure that minifying above
  // removed, at a guessable path. An app that does run a tracker turns this on
  // in its own copy of this file.
  //
  // 'inline' would be actively wrong here: the map is typically larger than the
  // minified code it describes, which would undo most of #107.
  sourcemap: nodeEnv !== 'production',
  // `keepNames` was tried here and removed. It preserves `Function.prototype.name`,
  // which is NOT what React >= 17 error frames report -- they name the JavaScript
  // function as the engine sees it, so the frames stayed minified (`at b` became
  // `at E`) and the hyper-component componentStack spec failed identically. It
  // cost 31,859 bytes (+7.6%) for no measured benefit, so it is not carried on an
  // unverified guess. Re-add it only with evidence that something actually reads
  // `.name` -- React DevTools display names are the plausible candidate, and that
  // is untested. (#107)
  logLevel: 'info',
}).catch(() => process.exit(1));
