require './ruby/version'

desc 'Publish hyperstack gems to private dir'
task :publish do
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
      sh 'gem' ,'push' ,"#{gem}-#{Hyperstack::VERSION.tr("'",'')}.gem" ,'--host' ,"https://michail:#{ENV['GEM_SERVER_KEY']}@gems.ru.aegean.gr"
    end
  end
end
