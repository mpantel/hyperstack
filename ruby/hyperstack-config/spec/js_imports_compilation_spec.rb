require 'spec_helper'
require 'opal'

# Guards the Opal-1.8 backtick trap in Hyperstack.js_import.
#
# `js_import` checks that each package it was told about actually reached the
# global object. The check used to be written:
#
#     next unless `Opal.global['#{name}'] === undefined`
#
# which looks right and is not. Opal does NOT interpolate `#{name}` inside the
# quoted subscript of a backtick, so it compiles to the LITERAL string:
#
#     Opal.global['name'] === undefined
#
# i.e. every package was checked against the one key `name` instead of its own.
# In a browser that is invisible, because `window.name` always exists, so the
# guard passes vacuously for every package and no one notices. Under V8
# prerendering `globalThis.name` is undefined, so it raised "The package X was
# not found" for the FIRST package every time -- which is why prerendering was
# stuck off (#19).
#
# The failure mode is what makes this worth a spec: it cannot be caught by any
# browser test, because the browser is precisely where the bug hides. So assert
# it where it is visible -- in the emitted JavaScript.
describe 'Hyperstack.js_import compiles its global-check correctly' do
  let(:source_path) do
    File.expand_path('../../lib/hyperstack/js_imports.rb', __FILE__)
  end

  let(:compiled) do
    # Opal 1.8 warns that bare backticks break in Opal 2.0; irrelevant here and
    # noisy, so keep it out of the spec output.
    original, $VERBOSE = $VERBOSE, nil
    begin
      Opal::Compiler.new(File.read(source_path)).compile
    ensure
      $VERBOSE = original
    end
  end

  it 'does not emit the literal string subscript' do
    expect(compiled).not_to include("Opal.global['name']"),
                            'js_imports.rb has regressed to `Opal.global[\'#{name}\']`, which Opal ' \
                            'compiles to the literal key \'name\'. Use `Opal.global[name]` -- the ' \
                            'bare local -- so each package is checked against its own key.'
  end

  it 'subscripts the global object with the loop variable' do
    expect(compiled).to match(/Opal\.global\[(?!['"])/),
                        'expected a non-literal subscript, e.g. Opal.global[name]'
  end

  # Pins the compiler behaviour the two expectations above rest on, so that if a
  # future Opal starts interpolating inside backticks this spec says which
  # assumption changed rather than just going red somewhere else.
  it 'documents why: Opal does not interpolate inside a quoted backtick subscript' do
    original, $VERBOSE = $VERBOSE, nil
    begin
      js = Opal::Compiler.new("name = 'Foo'\n`Opal.global['\#{name}']`\n").compile
    ensure
      $VERBOSE = original
    end
    expect(js).to include("Opal.global['name']")
  end
end
