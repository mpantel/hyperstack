require './ruby/version'


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

  # Reuse the credential CI already has for the private gem server:
  # BUNDLE_GEMS__RU__AEGEAN__GR is bundler's credential for
  # `source "https://gems.ru.aegean.gr"`, and that host IS this registry now, so
  # there is no second secret to provision. GEM_SERVER_TOKEN still wins if set,
  # for a token with different scope.
  #
  # Bundler stores a source credential as `user:password`, while this endpoint
  # wants the token alone -- so take everything after the first colon when the
  # value carries a username, and use it as-is when it does not.
  # `find`, not `||`: an empty string is TRUTHY in Ruby, and CI happily defines a
  # variable as "". `||` would then pick the empty one and never reach the real
  # credential -- the same trap documented in docker/cell-image/Dockerfile.
  raw = [ENV['GEM_SERVER_TOKEN'],
         ENV['BUNDLE_GEMS__RU__AEGEAN__GR'],
         ENV['GEM_SERVER_KEY']].find { |v| !v.to_s.empty? }
  if raw.to_s.empty?
    abort 'No gem-server credential: set GEM_SERVER_TOKEN (or BUNDLE_GEMS__RU__AEGEAN__GR) ' \
          'to a GitLab token with write_package_registry scope'
  end
  token = raw.include?(':') ? raw.split(':', 2).last : raw

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
  end

  namespace :gem do
    desc 'Build and publish ONE gem to the GitLab RubyGems registry (COMPONENT=hyper-model)'
    task :publish do
      component = ENV['COMPONENT'].to_s
      abort 'Set COMPONENT to the gem to publish, e.g. COMPONENT=hyper-model' if component.empty?
      dir = File.expand_path("ruby/#{component}", __dir__)
      abort "no such gem directory: #{dir}" unless Dir.exist?(dir)
      Dir.chdir(dir) { publish_gem(component) }
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

desc 'Publish hyperstack gems to private dir'
# NOTE for the rails-7+ rebase: those lines carry `task publish: 'version:check'`,
# so this becomes `task publish: ['version:check', 'hyperstack:matrix:check']`
# when the stack is replayed. Both prerequisites are wanted.
task publish: 'hyperstack:matrix:check' do
  base_path = ENV['PWD']
  #  hyper-console
  %w{
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
  }.each do|gem|
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
