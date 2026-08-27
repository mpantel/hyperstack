// esbuild build (#19). IIFE format (not esm) so the bundles set the window /
// Opal.global React globals immediately. Output -> app/assets/builds (served by
// sprockets). jsbundling-rails runs this via the package.json "build" script.
require('esbuild').build({
  entryPoints: [
    'app/javascript/react_runtime.js',        // client: window globals
    'app/javascript/react_server_runtime.js', // prerender (V8): Opal.global globals
  ],
  bundle: true,
  outdir: 'app/assets/builds',
  define: { 'process.env.NODE_ENV': JSON.stringify(process.env.NODE_ENV || 'production') },
  logLevel: 'info',
}).catch(() => process.exit(1));
