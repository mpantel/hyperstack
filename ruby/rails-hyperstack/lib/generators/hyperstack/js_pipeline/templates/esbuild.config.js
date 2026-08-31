// esbuild build (#19). IIFE format (not esm) so the bundles set the window /
// Opal.global React globals immediately. Output -> app/assets/builds (served by
// sprockets). jsbundling-rails runs this via the package.json "build" script.

// One signal for both `define` and `minify`, so a development build is
// development in both senses. Defaults to production: this bundle is served to
// every page of the app (application.js does `//= require react_runtime`), so
// the default has to be what ships, not what debugs. (#107)
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
