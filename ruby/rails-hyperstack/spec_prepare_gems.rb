# frozen_string_literal: true

# The gems `rake spec:prepare` needs installed in GEM_HOME before it can
# generate and boot the test app -- kept in ONE place because two things install
# them now (#73):
#
#   1. `spec:prepare` itself, for whatever is not already there (local dev), and
#   2. the cell image build, which bakes them in so CI stops paying for them once
#      per job (docker/cell-image/Dockerfile runs this file; the root Rakefile
#      exposes the same output as `rake hyperstack:cell:prepare_gems`).
#
# The versions are pinned literals, so copying them into the Dockerfile would
# re-open exactly the drift #51 exists to close. One list, two consumers -- the
# rule supported_versions.yml already follows for the matrix.
#
# Why these are in GEM_HOME and not in the bundle: `spec:prepare` shells out
# under `Bundler.with_unbundled_env` and runs plain `gem install`, so they never
# land in `local_gems` and the pipeline's gem cache never covered them -- which
# is why nokogiri 1.15.6 compiled from source on EVERY rails61 job (78s on
# base24, 202s on the cell image), and why re-enabling the cache for this job
# could not have helped.
module SpecPrepareGems
  module_function

  # The gems to install, as [name, version-or-nil] pairs. nil means "current
  # release", i.e. plain `gem install <name>`.
  def list(rails_version)
    gems = []
    if legacy_rails?(rails_version)
      # Rails 6.1 does not resolve against the current releases of these, and
      # the generated app inherits whatever `rails new` finds in GEM_HOME, so
      # the pins have to be in place BEFORE the generator runs.
      gems << ['zeitwerk',        '2.6.18']
      gems << ['nokogiri',        '1.15.6']
      gems << ['net-imap',        '0.4.18']
      gems << ['concurrent-ruby', '1.3.4']
    end
    gems << ['foreman', nil]
    gems << ['rails', rails_version]
    gems
  end

  # `gem install rails` drags newer copies of two of the pins in as
  # dependencies; drop those again so the pinned version is the only one
  # present. Safe to run when nothing matches -- `gem uninstall -v '> x'` prints
  # "Gem 'x' is not installed" and exits 0, leaving the pin alone -- which is
  # what happens on a prebaked image, where the build already did this.
  def surplus(rails_version)
    return [] unless legacy_rails?(rails_version)

    [['net-imap', '> 0.4.18'], ['concurrent-ruby', '> 1.3.4']]
  end

  # Read the major off the front so this answers the same for a resolved version
  # ("6.1.7.10") and for the requirement a cell selects with ("~> 7.2") -- a
  # plain string compare gets the latter wrong, because "~" sorts above "7".
  def legacy_rails?(rails_version)
    major = rails_version.to_s[/\d+/].to_i
    major.zero? ? rails_version.to_s < '7' : major < 7
  end

  # The whole sequence as shell, for the image build to execute.
  def install_commands(rails_version)
    list(rails_version).map { |name, version| install_command(name, version) } +
      surplus(rails_version).map { |name, req| uninstall_command(name, req) }
  end

  def install_command(name, version)
    version ? "gem install #{name} --version='#{version}'" : "gem install #{name}"
  end

  def uninstall_command(name, requirement)
    "gem uninstall #{name} --version '#{requirement}'"
  end

  # Which of `list` is not already installed in GEM_HOME.
  def missing(rails_version)
    list(rails_version).reject { |name, version| installed?(name, version) }
  end

  # Shelling out is deliberate: the caller runs under Bundler, where
  # Gem::Specification is filtered down to the *bundle*, not the GEM_HOME that
  # `gem install` writes to and that `rails new` then reads.
  def installed?(name, version)
    query = version ? "gem list -i #{name} --version='#{version}'" : "gem list -i #{name}"
    system("#{query} > /dev/null 2>&1")
  end

  # Gems Ruby 3.4 demoted from default gems to bundled gems, which Rails 6.1.7.x
  # (activesupport) still requires at boot. Under `bundle exec`, bundler drops
  # default gems that are not in the Gemfile from the load path, so without these
  # the generated app dies with "cannot load such file -- bigdecimal". See #11.
  #
  # Shared because the cell image generates a throwaway app of its own to warm
  # GEM_HOME and the yarn cache (#75), and that app has to boot for the same
  # reason this one does.
  def app_bundled_gems
    %w[bigdecimal mutex_m drb base64 logger]
  end

  # Which JavaScript pipeline the generated app is scaffolded with: Webpacker for
  # Rails < 7, esbuild + jsbundling for Rails >= 7, HYPERSTACK_JS_PIPELINE
  # overriding both. Mirrors the generator's own choice (see
  # generators/hyperstack/install_generator_base.rb #js_pipeline_name). (#51)
  #
  # Here rather than in the Rakefile because the image build has to make the same
  # call -- it decides whether the warm-up app is scaffolded with
  # `--skip-javascript` and whether `webpacker:install` is what fills the yarn
  # cache (#75).
  def js_pipeline(rails_version)
    return ENV['HYPERSTACK_JS_PIPELINE'] unless ENV['HYPERSTACK_JS_PIPELINE'].to_s.empty?

    legacy_rails?(rails_version) ? 'webpacker' : 'esbuild'
  end

  # The version this cell's bundle actually resolved -- exactly how
  # `spec:prepare` picks it -- so the image and the job install the same rails
  # rather than the image installing whatever the cell's requirement floats to.
  def resolved_rails_version(dir = __dir__)
    info = Dir.chdir(dir) { `bundle info rails 2>/dev/null` }
    resolved = info[/\* rails \((.+)\)/, 1]
    return resolved if resolved

    # No bundle to ask (nothing installed yet). The cell's own requirement is
    # the next best answer, and `gem install --version` takes one as happily as
    # it takes an exact version.
    requirement = ENV['RAILS_VERSION'].to_s
    return requirement unless requirement.empty?

    raise "cannot determine the rails version: `bundle info rails` found nothing in #{dir} " \
          'and RAILS_VERSION is unset'
  end
end

# Run directly, this is the cell image build's interface (the root Rakefile's
# `hyperstack:cell:prepare_gems` prints the same thing):
#
#   ruby spec_prepare_gems.rb                     the shell to run
#   ruby spec_prepare_gems.rb --verify            exit non-zero unless all of it landed
#   ruby spec_prepare_gems.rb --rails-version     the resolved rails version
#   ruby spec_prepare_gems.rb --js-pipeline       webpacker | esbuild, for this cell
#   ruby spec_prepare_gems.rb --app-bundled-gems  what the generated app must declare
#
# --verify is what earns the image the right to set HYPERSTACK_PREBAKED_SPEC_GEMS:
# without it a silently failed install would ship an image that promises these
# gems, and the promise is what makes the job abort instead of installing them.
if $PROGRAM_NAME == __FILE__
  rails_version = SpecPrepareGems.resolved_rails_version

  if ARGV.include?('--rails-version')
    puts rails_version
  elsif ARGV.include?('--js-pipeline')
    puts SpecPrepareGems.js_pipeline(rails_version)
  elsif ARGV.include?('--app-bundled-gems')
    puts SpecPrepareGems.app_bundled_gems
  elsif ARGV.include?('--verify')
    missing = SpecPrepareGems.missing(rails_version)
    unless missing.empty?
      warn "spec:prepare gems missing after install: " \
           "#{missing.map { |name, version| [name, version].compact.join(' ') }.join(', ')}"
      exit 1
    end
    puts "spec:prepare gems present for rails #{rails_version}: " \
         "#{SpecPrepareGems.list(rails_version).map(&:first).join(', ')}"
  else
    puts SpecPrepareGems.install_commands(rails_version)
  end
end
