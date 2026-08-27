# Which React a gem's spec/test_app serves, applied at spec:prepare time (#40).
#
# A test_app can take React from two places:
#
#   gem  - the react-rails gem over sprockets. REACT_RAILS_VERSION selects it,
#          and it reaches 16.14 / 17.0.2 / 18.2. This is the default.
#   npm  - react + react-dom from npm, bundled by esbuild into
#          app/assets/builds/react_runtime.js. REACT_NPM_VERSION selects it.
#          This is the only way to reach React 19.
#
# The wiring is applied HERE rather than committed into each test_app because it
# is a per-cell choice. Committing it would force every cell onto the same React
# and collapse the rails61-react16/17/18 cells into one, which is the opposite of
# what the matrix is for. It also keeps ONE copy of the four scaffolding files
# instead of five near-identical copies under ruby/*/spec/test_app.
#
# The scaffolding files are not copies: this reads the SAME four templates
# rails-hyperstack's esbuild generator writes into a real application
# (generators/hyperstack/js_pipeline/templates). They were heredocs inside that
# generator until #40 gave them a second consumer; as heredocs the two copies
# could drift and the suite would be proving a runtime we do not actually ship.
#
# Every step is idempotent: a re-prepared app is not double-wired.
require 'fileutils'

module TestAppReactSource
  TEMPLATES = File.expand_path(
    'rails-hyperstack/lib/generators/hyperstack/js_pipeline/templates', __dir__
  )

  # The tracked files the npm path rewrites in place. Originals are copied into
  # BACKUP_DIR before the first rewrite and put back when a later prepare runs on
  # the gem path, so the React source is a per-run choice in a local checkout too.
  #
  # Without this the wiring is one-way: the rewrites are idempotent and nothing
  # undoes them, so one npm run leaves application.js requiring react_runtime and
  # the react-rails imports cancelled -- and every subsequent gem-path run in that
  # checkout quietly keeps serving React 19 while claiming to be a React 16/17/18
  # cell. CI never sees this (fresh checkout per job); a developer would.
  REWRITTEN = %w[
    app/assets/javascripts/application.js
    app/assets/config/manifest.js
    config/initializers/hyperstack.rb
    config/initializers/assets.rb
    package.json
  ].freeze

  BACKUP_DIR = '.react_source_backup'.freeze
  # marks a file that did not exist before the npm path created it
  ABSENT = "#{BACKUP_DIR}/.absent".freeze

  # Where each template lands inside the test_app.
  SCAFFOLD = {
    'react_runtime.js'        => 'app/javascript/react_runtime.js',
    'react_server_runtime.js' => 'app/javascript/react_server_runtime.js',
    'text_encoder_polyfill.js' => 'app/javascript/text_encoder_polyfill.js',
    'esbuild.config.js'       => 'esbuild.config.js'
  }.freeze

  module_function

  def source
    ENV['HYPERSTACK_REACT_SOURCE'] || 'gem'
  end

  def npm_version
    ENV['REACT_NPM_VERSION'] || '^19.0.0'
  end

  # Returns true when it actually rewired, so callers can log it.
  def apply!(app_dir = 'spec/test_app')
    # hyper-trace has no test_app, and rails-hyperstack generates its own (the
    # esbuild generator does all of this for it). Both are a no-op here.
    return false unless Dir.exist?(app_dir)

    unless source == 'npm'
      restore!(app_dir) # undo a previous npm run in this checkout
      return false
    end

    back_up(app_dir)
    install_scaffold(app_dir)
    write_package_json(app_dir)
    require_react_runtime(app_dir)
    cancel_gem_react(app_dir)
    link_builds(app_dir)
    add_builds_paths(app_dir)
    build(app_dir)
    true
  end

  # Copy each rewritten file aside once, before the first rewrite touches it. A
  # file that does not exist yet (package.json in most apps) is recorded by name
  # in .absent so restore! deletes it rather than leaving a stray behind.
  def back_up(app_dir)
    dir = File.join(app_dir, BACKUP_DIR)
    return if Dir.exist?(dir) # already backed up; do not capture rewritten files

    FileUtils.mkdir_p(dir)
    absent = []
    REWRITTEN.each do |rel|
      src = File.join(app_dir, rel)
      if File.exist?(src)
        dest = File.join(dir, rel)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(src, dest)
      else
        absent << rel
      end
    end
    File.write(File.join(app_dir, ABSENT), absent.join("\n"))
  end

  # Put the app back the way the repository has it. Idempotent, and a no-op in a
  # checkout that has never run the npm path.
  def restore!(app_dir)
    dir = File.join(app_dir, BACKUP_DIR)
    return false unless Dir.exist?(dir)

    absent = File.exist?(File.join(app_dir, ABSENT)) ? File.read(File.join(app_dir, ABSENT)).split("\n") : []
    REWRITTEN.each do |rel|
      saved = File.join(dir, rel)
      target = File.join(app_dir, rel)
      if File.exist?(saved)
        FileUtils.cp(saved, target)
      elsif absent.include?(rel)
        FileUtils.rm_f(target)
      end
    end
    # The placed scaffolding and the esbuild output are gitignored and inert once
    # nothing requires them, but remove them too so `gem` means gem.
    SCAFFOLD.each_value { |rel| FileUtils.rm_f(File.join(app_dir, rel)) }
    FileUtils.rm_rf(File.join(app_dir, 'app/assets/builds'))
    FileUtils.rm_rf(dir)
    puts '  [react-source] restored the react-rails wiring (HYPERSTACK_REACT_SOURCE=gem)'
    true
  end

  def install_scaffold(app_dir)
    SCAFFOLD.each do |template, target|
      path = File.join(app_dir, target)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, File.read(File.join(TEMPLATES, template), encoding: 'UTF-8'))
    end
  end

  # A test_app either has no package.json at all (most of them) or an empty stub
  # (hyper-component). Either way the dependency set is fully determined by the
  # scaffold we just wrote, so write the whole file rather than patching it --
  # patching is what let hyper-component's stub keep an empty "dependencies" and
  # produce a bundle with no React in it.
  #
  # The list mirrors the generator's package.json. react-router/history are here
  # for hyper-router; they cost one npm package in the other apps and keep a
  # single shared react_runtime.js valid everywhere.
  def write_package_json(app_dir)
    File.write(File.join(app_dir, 'package.json'), <<~JSON)
      {
        "name": "test_app",
        "private": true,
        "scripts": {
          "build": "node esbuild.config.js"
        },
        "dependencies": {
          "create-react-class": "^15.7.0",
          "history": "^4.10.1",
          "react": "#{npm_version}",
          "react-dom": "#{npm_version}",
          "react-router": "^5.3.4",
          "react-router-dom": "^5.3.4"
        },
        "devDependencies": {
          "esbuild": "^0.23.0"
        }
      }
    JSON
  end

  # BEFORE the Opal loader, so window.React exists on every page that loads
  # application.js -- including the hyper-spec harness, which has no layout.
  #
  # Two shapes of application.js exist across the test_apps:
  #
  #   //= require hyperstack-loader          (hyper-component, hyper-model, hyper-router)
  #   //= require 'react'                    (hyper-state, hyper-store, hyper-spec)
  #   //= require 'react_ujs'
  #   //= require 'components'
  #
  # The second shape pulls the react-rails UMD in directly, so requiring
  # react_runtime is not enough -- that line has to go, or the page loads two
  # Reacts and the last one wins (the defect in #66). react_ujs STAYS: it is the
  # mount shim, not a React source, and it reads whichever global React it finds.
  def require_react_runtime(app_dir)
    path = File.join(app_dir, 'app/assets/javascripts/application.js')
    return unless File.exist?(path)

    body = File.read(path, encoding: 'UTF-8')
    body = body.gsub(%r{^//=\s*require\s+['"]?react['"]?\s*$}, "//= require react_runtime")
    unless body.include?('require react_runtime')
      # hyper-i18n quotes the loader (`//= require 'hyperstack-loader'`); match either.
      loader = %r{^//=\s*require\s+['"]?hyperstack-loader['"]?}
      body = if body =~ loader
               body.sub(/(#{loader})/, "//= require react_runtime\n\\1")
             else
               "//= require react_runtime\n#{body}"
             end
    end
    File.write(path, body)
  end

  # Drop the react-rails sprockets React so it cannot load a second React over
  # the esbuild one -- the defect in #66, where load order silently won.
  # Drop EVERY react-rails React the app pulls in, then add the prerender bundle.
  #
  # Removing only `import 'react'` is not enough, and getting this wrong is
  # expensive: hyper-component's app also has
  #
  #   Hyperstack.import 'react-server', js_import: true, at_head: true, client_only: true
  #
  # which loads react-rails' *server* React source ON THE CLIENT. Left in place
  # alongside npm React 19 that is two Reacts in one page, and React fails with an
  # internal invariant -- 185 x "Minified React error #525" across the suite,
  # which reads like a React 19 incompatibility and is not one.
  #
  # hyperstack/router/react-router-source is hyper-router's bundled ReactRouter
  # UMD; under esbuild react-router comes from npm through react_runtime, so that
  # one goes too. cancel_import is a safe no-op where hyper-router isn't loaded (#32).
  #
  # react_server_runtime is imported at_head for the prerender bundle so its
  # globals are set after Opal boots and before the React defines-check.
  def cancel_gem_react(app_dir)
    path = File.join(app_dir, 'config/initializers/hyperstack.rb')
    return unless File.exist?(path)

    body = File.read(path, encoding: 'UTF-8')
    # Any react-rails React import, client or server. Leading whitespace is
    # allowed: hyper-i18n's sits indented inside a `Hyperstack.configuration`
    # block, and an anchored `^Hyperstack\.import` walked straight past it,
    # leaving that app with npm React 19 AND the react-rails UMD in one page.
    body = body.gsub(/^[ \t]*Hyperstack\.import 'react(-server)?', js_import: true.*$\n?/, '')
    unless body.include?("cancel_import 'react/react-source-browser'")
      body += "\n# #40: React comes from npm via esbuild (app/assets/builds/react_runtime.js).\n" \
              "Hyperstack.cancel_import 'react/react-source-browser'\n" \
              "Hyperstack.cancel_import 'react/react-source-server'\n" \
              "Hyperstack.cancel_import 'hyperstack/router/react-router-source'\n"
    end
    unless body.include?("import 'react_server_runtime'")
      body += "Hyperstack.import 'react_server_runtime', js_import: true, " \
              "server_only: true, at_head: true\n"
    end
    File.write(path, body)
  end

  def link_builds(app_dir)
    path = File.join(app_dir, 'app/assets/config/manifest.js')
    return unless File.exist?(path)

    body = File.read(path, encoding: 'UTF-8')
    return if body.include?('link_tree ../builds')

    File.write(path, "#{body.rstrip}\n//= link_tree ../builds\n")
  end

  # app/assets/builds must be on BOTH sprockets' asset paths and Opal's load
  # path -- they are separate, and the prerender bundle's
  # `require 'react_server_runtime'` resolves via Opal's.
  # Inserted EARLY, right after the first assets.paths line -- not appended.
  # Appending puts it after `Opal::Config.source_map_enabled = ...`, and by then
  # Opal's load path array is frozen: `FrozenError: can't modify frozen Array`
  # out of Opal.append_paths. rails-7's working test_app has it in the same early
  # position, which is what made that one boot.
  def add_builds_paths(app_dir)
    path = File.join(app_dir, 'config/initializers/assets.rb')
    return unless File.exist?(path)

    body = File.read(path, encoding: 'UTF-8')
    return if body.include?("'builds'")

    block = <<~RUBY
      # #40: esbuild output, on both sprockets' and Opal's load paths -- they are
      # separate, and the prerender bundle resolves via Opal's.
      Rails.application.config.assets.paths << Rails.root.join('app', 'assets', 'builds').to_s
      require 'opal'
      Opal.append_path Rails.root.join('app', 'assets', 'builds').to_s
    RUBY

    lines = body.lines
    anchor = lines.index { |l| l =~ /assets\.paths\s*<</ && l !~ /^\s*#/ }
    if anchor
      lines.insert(anchor + 1, block)
      File.write(path, lines.join)
    else
      File.write(path, block + body)
    end
  end

  def build(app_dir)
    Dir.chdir(app_dir) do
      sh 'yarn install --silent'
      sh 'yarn build'
    end
  end

  def sh(cmd)
    puts "  [react-source] #{cmd}"
    raise "#{cmd} failed" unless system(cmd)
  end
end
