require './ruby/version'

# The gems this repo publishes. ONE list, two consumers -- `rake publish` walks
# it, and every `*-deploy` job in .gitlab-ci.yml must name one of them, asserted
# by `rake hyperstack:gem:check`. Same "one table, two consumers" rule
# supported_versions.yml follows for cells (#51): the pipeline and the Rakefile
# each carried their own hardcoded copy of this list, agreeing only by care,
# with nothing to notice when they stopped.
PUBLISHED_GEMS = %w[
  hyper-component
  hyper-i18n
  hyper-model
  hyper-operation
  hyper-router
  hyper-spec
  hyper-state
  hyper-store
  hyper-trace
  hyperstack-config
  rails-hyperstack
].freeze

# Has a gemspec but is deliberately not published. Listed rather than merely
# absent, so `hyperstack:gem:check` can tell "excluded on purpose" from "someone
# added a gem and forgot the deploy job".
DELIBERATELY_UNPUBLISHED = %w[hyper-console].freeze # untested by CI, frozen on React 15 (#86)

# Published, but deliberately has NO test job in .gitlab-ci.yml. Same "listed
# rather than merely absent" rule as above, for the same reason: an unexplained
# gap is indistinguishable from an accident.
#
# hyper-trace has no `spec/` directory and never has. Its job therefore ran bare
# `rake` -> the no-op `:default` task -> exit 0 with zero examples, ten times a
# pipeline, reporting the gem green across the whole support matrix. That is a
# false green, so the job was removed rather than left as decoration (#121).
#
# It is still published: it is a hand-invoked client-side debugging tool
# (`SomeClass.hypertrace instrument: :all` traces methods to the browser console),
# it is a development dependency only -- never a runtime dependency of any gem
# here -- and rails-hyperstack's generators do not put it in a generated app. So
# nothing installs it unless a developer asks for it, and it is inert until they
# call `hypertrace` by hand.
UNTESTED_BY_CI = %w[hyper-trace].freeze


# Publishing moved off geminabox: gems.ru.aegean.gr was repointed to GitLab's
# RubyGems Package Registry (ru/rubygems, project 65) on 2026-08-18 and the
# standalone gemserver container is stopped. (#49)
#
# `gem push` cannot be used at all here -- gems built against the old host carry
# an `allowed_push_host` the RubyGems client refuses to override -- and neither
# can the old `curl -F` multipart upload: GitLab answers 201, then stores the
# form envelope as the gem, the extraction worker fails, and a broken
# `Gem.Temporary.Package` is left behind. The file must be POSTed as a RAW body,
# the way `gem push` sends it, with a PLAIN token header (`Bearer` and
# `PRIVATE-TOKEN` are both rejected by this endpoint).
#
# Ported from ru/hyperstack-addons' Rakefile `publish` task, which already
# solved this.
def publish_gem(gem, version = Hyperstack::VERSION.tr("'", ''))
  require 'net/http'
  require 'uri'
  require 'json'

  # Credential order matters, and it changed after the 1.0.alpha1.9 publish
  # attempt returned `HTTP 403 Forbidden` on every gem.
  #
  # The old order put BUNDLE_GEMS__RU__AEGEAN__GR second, which is bundler's
  # credential for `source "https://gems.ru.aegean.gr"` -- i.e. the credential
  # for READING gems. It is project 65's `capistrano-deploy-rubygems` deploy
  # token, whose only scope is `read_package_registry`, so it can never upload.
  # Nothing else in the `ru` group has write access either: the group's one
  # deploy token is `read_registry` (Docker).
  #
  # So prefer CI_JOB_TOKEN, which every job already has, is scoped to that job,
  # expires with it, and needs no secret stored anywhere. It requires ru/hyperstack
  # to be on ru/rubygems' CI job token INBOUND allowlist (project 65 has
  # `inbound_enabled: true`); without that the registry answers 403 exactly as the
  # read-only token did, so the abort message below names it.
  #
  # GEM_SERVER_TOKEN still wins outright, for an explicitly provisioned token.
  # The two read credentials stay last as a fallback for a local publish, where
  # there is no job token -- and where the human running it can be told plainly
  # that a read scope will fail.
  #
  # `find`, not `||`: an empty string is TRUTHY in Ruby, and CI happily defines a
  # variable as "". `||` would then pick the empty one and never reach the real
  # credential -- the same trap documented in docker/cell-image/Dockerfile.
  job_token = ENV['CI_JOB_TOKEN'].to_s
  explicit  = [ENV['GEM_SERVER_TOKEN'],
               ENV['BUNDLE_GEMS__RU__AEGEAN__GR'],
               ENV['GEM_SERVER_KEY']].find { |v| !v.to_s.empty? }

  # EVERY credential goes in a plain `Authorization` header, the job token
  # included. This endpoint reads only that header -- it already rejected `Bearer`
  # and `PRIVATE-TOKEN`, and a first attempt at sending the job token as
  # `JOB-TOKEN` was rejected too.
  #
  # The status codes are what settle it, and they are worth keeping:
  #
  #   Authorization: <read-only deploy token>  -> 403 Forbidden
  #   JOB-TOKEN:     <CI_JOB_TOKEN>            -> 401 Unauthorized
  #
  # 403 means authenticated but not permitted; 401 means not authenticated at
  # all. So the deploy token WAS read from Authorization and merely lacked
  # write_package_registry, while the job token in JOB-TOKEN was not read at all.
  # The header is the variable, not the credential.
  token = [ENV['GEM_SERVER_TOKEN'], job_token, explicit].find { |v| !v.to_s.empty? }
  if token.to_s.empty?
    abort 'No gem-server credential. In CI this should be CI_JOB_TOKEN (ru/hyperstack ' \
          "must be on ru/rubygems' CI job token inbound allowlist); locally set " \
          'GEM_SERVER_TOKEN to a GitLab token with write_package_registry scope.'
  end

  # Bundler stores a source credential as `user:password`, while this endpoint
  # wants the token alone -- so take everything after the first colon when the
  # value carries a username, and use it as-is when it does not. Job tokens never
  # carry a username, but the split is harmless for them.
  token = token.include?(':') ? token.split(':', 2).last : token

  host       = ENV['GEM_SERVER_HOST'] || 'https://gitlab.ru.aegean.gr'
  project_id = ENV['GEM_SERVER_PROJECT_ID'] || '65' # ru/rubygems
  registry   = "#{host}/api/v4/projects/#{project_id}/packages/rubygems"
  gem_file   = "#{gem}-#{version}.gem"

  sh 'gem', 'build', "#{gem}.gemspec"

  uri = URI("#{registry}/api/v1/gems")
  request = Net::HTTP::Post.new(uri)
  request['Authorization'] = token
  request['Content-Type']  = 'application/octet-stream'
  request.body = File.binread(gem_file)
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.request(request)
  end
  unless response.code == '201'
    abort "Upload of #{gem_file} failed: HTTP #{response.code} #{response.body}"
  end
  puts "Uploaded #{gem_file} to #{registry}"

  # 201 only means the file was stored; GitLab extracts the gemspec
  # asynchronously, so poll until the version appears with status "default".
  list = URI("#{host}/api/v4/projects/#{project_id}/packages?package_name=#{gem}&per_page=100")
  10.times do
    sleep 2
    check = Net::HTTP::Get.new(list)
    check['Authorization'] = token
    result = Net::HTTP.start(list.hostname, list.port, use_ssl: list.scheme == 'https') do |http|
      http.request(check)
    end
    next unless result.code == '200'

    package = JSON.parse(result.body).find { |pkg| pkg['version'] == version }
    next if package.nil?

    case package['status']
    when 'default'
      puts "Published #{gem} #{version} (package #{package['id']})"
      return true
    when 'error'
      abort "Package #{package['id']} is in state 'error' - delete it and retry"
    end
  end
  puts "Uploaded, but #{gem} #{version} has not appeared in #{registry} yet - check the registry."
  false
end

namespace :hyperstack do
  namespace :config do
    desc 'Check the current ruby/rails/opal/react-rails combination against supported_versions.yml'
    task :check do
      $LOAD_PATH.unshift File.expand_path('ruby/hyperstack-config/lib', __dir__)
      require 'hyperstack/supported_versions'
      sv = Hyperstack::SupportedVersions
      puts sv.describe
      case sv.status
      when :unsupported then abort 'hyperstack:config:check FAILED'
      when :unknown     then puts 'hyperstack:config:check SKIPPED (nothing detectable)'
      end
    end
  end

  namespace :cell do
    desc 'Print shell exports for HYPERSTACK_CELL (used by CI: eval "$(rake hyperstack:cell:env)")'
    task :env do
      require 'yaml'
      id = ENV['HYPERSTACK_CELL'].to_s
      table = YAML.safe_load(File.read(File.expand_path('supported_versions.yml', __dir__), encoding: 'UTF-8'))
      cell = table['cells'].detect { |c| c['id'] == id }
      abort "unknown HYPERSTACK_CELL #{id.inspect}; known: #{table['cells'].map { |c| c['id'] }.join(', ')}" unless cell
      # Values come from the table, never from .gitlab-ci.yml, so the pipeline
      # names cells and the table defines them. A cell with no env takes the
      # gemspec defaults.
      (cell['env'] || {}).each { |k, v| puts "export #{k}=#{v.to_s.inspect}" }
    end

    desc "Print the `gem install` lines rails-hyperstack's spec:prepare needs (baked into the cell image, #73)"
    task :prepare_gems do
      # The list itself lives next to the task that consumes it, so the image
      # build and `rake spec:prepare` read one definition and cannot disagree
      # about versions -- the drift rule #51 set for the matrix. The image build
      # runs that file directly (docker/cell-image/Dockerfile) to keep the root
      # Rakefile out of the docker context, where it would invalidate the
      # bundle layer on every unrelated edit; this task is the same output for
      # anyone asking from the repo.
      require_relative 'ruby/rails-hyperstack/spec_prepare_gems'
      puts SpecPrepareGems.install_commands(SpecPrepareGems.resolved_rails_version)
    end
  end

  namespace :gem do
    desc 'Build and publish ONE gem to the GitLab RubyGems registry (COMPONENT=hyper-model)'
    task :publish do
      component = ENV['COMPONENT'].to_s
      abort 'Set COMPONENT to the gem to publish, e.g. COMPONENT=hyper-model' if component.empty?
      abort "#{component} is not in PUBLISHED_GEMS" unless PUBLISHED_GEMS.include?(component)

      dir = File.expand_path("ruby/#{component}", __dir__)
      abort "no such gem directory: #{dir}" unless Dir.exist?(dir)
      Dir.chdir(dir) { publish_gem(component) }
    end

    desc 'Verify .gitlab-ci.yml deploy jobs match PUBLISHED_GEMS (one list, two consumers)'
    task :check do
      require 'yaml'
      ci = File.read(File.expand_path('.gitlab-ci.yml', __dir__), encoding: 'UTF-8')
      # Every job extending .deploy_gem names its gem in COMPONENT. That is the
      # pipeline's copy of the list; PUBLISHED_GEMS is ours.
      in_ci = ci.scan(/extends:\s*\.deploy_gem\s*\n\s*variables:\s*\n\s*COMPONENT:\s*(\S+)/)
                .flatten.sort
      declared = PUBLISHED_GEMS.sort

      msg = []
      (declared - in_ci).tap { |x| msg << "declared but no deploy job: #{x.join(', ')}" if x.any? }
      (in_ci - declared).tap { |x| msg << "deploy job but not declared: #{x.join(', ')}" if x.any? }

      # A gem that exists on disk and is in neither list is the dangerous case:
      # it ships to nobody and nothing says so. hyper-console is the one
      # deliberate exclusion (#86) and is named so that adding a gem cannot be
      # forgotten the same way.
      on_disk = Dir[File.expand_path('ruby/*/*.gemspec', __dir__)]
                .map { |p| File.basename(File.dirname(p)) }.sort
      unaccounted = on_disk - declared - DELIBERATELY_UNPUBLISHED
      msg << "gemspec on disk, published by nothing: #{unaccounted.join(', ')}" if unaccounted.any?

      # Same rule again for TEST jobs, which is how #121 stayed invisible: a gem
      # can have a job that runs nothing, or lose its job entirely, and the only
      # signal either way is a green pipeline. Every job extending a .test_gem*
      # template names its gem in COMPONENT (hyper-operation has two, part1 and
      # part2, hence .uniq). `supported-versions` deliberately does not extend
      # the template, so it is correctly not counted here.
      #
      # PARSED, not pattern-matched. The first version of this scanned for
      # `extends:` followed directly by `variables:` then `COMPONENT:`, which
      # broke the moment #116 put an explanatory comment between `variables:`
      # and `COMPONENT:` in the hyper-i18n job -- the gem silently stopped
      # counting as tested and this check failed on edge. Structure that YAML
      # considers irrelevant must not change the answer, so ask the parser.
      ci_yaml = YAML.safe_load(File.read(File.expand_path('.gitlab-ci.yml', __dir__), encoding: 'UTF-8'), aliases: true)
      tested = ci_yaml.filter_map do |name, body|
        next if name.start_with?('.')          # templates, not jobs
        next unless body.is_a?(Hash)
        extends = Array(body['extends']).map(&:to_s)
        next unless extends.any? { |e| e.start_with?('.test_gem') }
        body.dig('variables', 'COMPONENT')
      end.compact.uniq.sort
      (declared - UNTESTED_BY_CI - tested).tap do |x|
        msg << "published but no test job, and not listed in UNTESTED_BY_CI: #{x.join(', ')}" if x.any?
      end
      (UNTESTED_BY_CI & tested).tap do |x|
        msg << "listed in UNTESTED_BY_CI but has a test job: #{x.join(', ')}" if x.any?
      end

      abort "hyperstack:gem:check FAILED — #{msg.join('; ')}" if msg.any?

      puts "hyperstack:gem:check OK — #{declared.size} gem(s) published, " \
           "#{DELIBERATELY_UNPUBLISHED.size} deliberately excluded " \
           "(#{DELIBERATELY_UNPUBLISHED.join(', ')}), " \
           "#{tested.size} with test jobs, " \
           "#{UNTESTED_BY_CI.size} published without one (#{UNTESTED_BY_CI.join(', ')})"
    end
  end

  namespace :matrix do
    desc 'Verify .gitlab-ci.yml cells match supported_versions.yml (one table, two consumers)'
    task :check do
      require 'yaml'
      # explicit UTF-8: CI runners set no locale, so Ruby would default the
      # external encoding to US-ASCII and choke on any non-ASCII byte
      table = YAML.safe_load(File.read(File.expand_path('supported_versions.yml', __dir__), encoding: 'UTF-8'))
      declared = table['cells'].map { |c| c['id'] }.sort
      ci = File.read(File.expand_path('.gitlab-ci.yml', __dir__), encoding: 'UTF-8')
      # Each cell must appear as a HYPERSTACK_CELL value in the pipeline, so a
      # combination we claim to support is one that actually gets tested. Handles
      # both the scalar form and the `parallel: matrix:` list form
      # (`HYPERSTACK_CELL: [a, b]`).
      present = ci.scan(/HYPERSTACK_CELL:\s*(\[[^\]]*\]|["']?[\w.-]+)/).flatten.flat_map do |raw|
        raw.start_with?('[') ? raw.tr('[]"\'', '').split(',') : [raw.delete('"\'')]
      end.map(&:strip).reject(&:empty?).sort.uniq
      missing = declared - present
      extra   = present - declared
      if missing.empty? && extra.empty?
        puts "hyperstack:matrix:check OK — #{declared.size} cell(s): #{declared.join(', ')}"
      else
        msg = []
        msg << "declared in supported_versions.yml but not run by CI: #{missing.join(', ')}" if missing.any?
        msg << "run by CI but not declared: #{extra.join(', ')}" if extra.any?
        abort "hyperstack:matrix:check FAILED — #{msg.join('; ')}"
      end
    end
  end
end

desc 'Publish hyperstack gems to the GitLab RubyGems registry'
task publish: ['hyperstack:matrix:check', 'hyperstack:gem:check'] do
  base_path = ENV['PWD']
  PUBLISHED_GEMS.each do |gem|
    puts "Publishing #{gem} gem"
    Dir.chdir("#{base_path}/ruby/#{gem}") do
      puts "Delete #{gem} Gemfile.lock"
      File.delete('Gemfile.lock') if File.exist?('Gemfile.lock')
      puts "Bundling..."
      sh ['bundle','install']
      # was: gem build + `curl -F ... @gems.ru.aegean.gr/upload` (geminabox).
      # publish_gem builds and uploads the way the GitLab registry requires. (#49)
      publish_gem(gem)
    end
  end
end
