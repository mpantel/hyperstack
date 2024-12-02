Hyperstack.configuration do |config|
  Hyperstack.import 'react', js_import: true, at_head: true
  config.transport = :none
  config.import 'hyper-model'
end
