# client_option javascript: 'factorial' serves this file instead of
# application.js, so it has to stand on its own.
#
# It must not require "application" -- that is a sprockets JS manifest, not an
# Opal module, so on the opal-sprockets pipeline (Rails 8) it compiles to a
# runtime Opal.require call that throws before factorial is defined. Nor may it
# require "components": that pulls in hyper-component, which needs the React and
# ReactDOM globals only the application.js manifest brings in.
#
# So require exactly what this file needs: opal for the runtime (nothing else
# here pulls it in), and json, because hyper-spec's Rails harness makes json! a
# no-op yet reads results back by calling to_json on them. (#20)
#
# Keep sprockets directive syntax out of these comments -- sprockets parses the
# leading comment block, and a stray require directive in prose fails the asset
# with "wrong number of arguments".
require 'opal'
require 'json'

def factorial(n)
  n == 1 ? 1 : n * factorial(n - 1)
end
