require './ruby/version'

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

  namespace :matrix do
    desc 'Verify .gitlab-ci.yml cells match supported_versions.yml (one table, two consumers)'
    task :check do
      require 'yaml'
      table = YAML.safe_load(File.read(File.expand_path('supported_versions.yml', __dir__)))
      declared = table['cells'].map { |c| c['id'] }.sort
      ci = File.read(File.expand_path('.gitlab-ci.yml', __dir__))
      # Each cell must appear as a HYPERSTACK_CELL value in the pipeline, so a
      # combination we claim to support is one that actually gets tested.
      present = ci.scan(/HYPERSTACK_CELL:\s*["']?([\w.-]+)/).flatten.sort.uniq
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
      sh 'gem' ,'build', "#{gem}.gemspec"
      sh 'curl', '-F', "file=@#{gem}-#{Hyperstack::VERSION.tr("'",'')}.gem", "https://michail:#{ENV['GEM_SERVER_KEY']}@gems.ru.aegean.gr/upload"
    end
  end
end
