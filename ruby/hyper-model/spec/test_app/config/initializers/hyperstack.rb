Hyperstack.import 'hyperstack/pusher', client_only: true
Hyperstack.cancel_import 'hyperstack/autoloader'
Hyperstack.cancel_import 'hyperstack/autoloader_starter'
Hyperstack.cancel_import 'config/initializers/inflections.rb'

Hyperstack.import 'react', js_import: true, at_head: true
def (Hyperstack::Connection).build_tables?; false; end
