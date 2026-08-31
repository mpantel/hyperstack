# rubocop:disable Style/FileName

# The router for the SPROCKETS delivery path: three UMD builds vendored into
# lib/src, js_import'ed by hyper-router.rb as ReactRouter / ReactRouterDOM /
# History. The esbuild path does not use them -- js_pipeline/esbuild.rb cancels
# this import and takes react-router from npm instead.
#
# What is actually in lib/src, verified by md5 against the published unpkg
# artifacts rather than assumed (#124):
#
#     react-router.min.js       react-router@4.2.0       22,396 bytes
#     react-router-dom.min.js   react-router-dom@4.2.2   47,322 bytes
#     history.min.js            history@4.7.2            15,213 bytes
#
# That record used to live in ruby/hyper-router/package.json, a file nothing read:
# it is not in the gemspec's `spec.files` (`Dir['{lib}/**/*'] + ['Rakefile']`),
# no Rakefile, generator or CI job opened it, and no npm install ever ran in this
# directory. It was accurate about these three -- all three md5s match its
# declarations exactly -- but it also declared `react`/`react-dom` `^15.6.1`,
# two majors below the matrix floor and a React this gem has never been the
# source of. So it read as a dependency declaration while being a provenance
# note, and the only version in it anyone could act on was wrong. Deleted; the
# part that was true is here, next to the files it describes.
#
# So the two delivery paths run DIFFERENT router majors, and both are supported
# by hyper-router's DSL, which is the react-router 4/5 API either way:
#
#     sprockets cells (react 16.14 / 17.0.2 / 18.2)   react-router 4.2.0, here
#     npm cells       (react 19.2)                    react-router 5.3.4, npm
#
# Which also answers what #40 has to know before it widens the npm route to the
# React 16/17/18 cells: those cells move from 4.2.0 to 5.3.4, a NEWER router on
# an older React, and 5.3.4's peer range is `react: >=15` -- so they stay inside
# it. See Hyperstack::ReactNpmDependencies for why the npm side is pinned where
# it is.
require 'src/react-router.min.js'
require 'src/react-router-dom.min.js'
require 'src/history.min.js'
