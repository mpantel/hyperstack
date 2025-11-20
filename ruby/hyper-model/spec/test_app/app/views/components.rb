require 'opal'
require 'hyper-component'
if Hyperstack::Component::IsomorphicHelpers.on_opal_client?
  require 'browser'
  require 'browser/delay'
  require 'browser/interval'
  #require 'hyperstack/pusher'
end
require 'hyper-model'
require '_react_public_models'

# Define HyperComponent base class before loading components
class HyperComponent
  include Hyperstack::Component
  include Hyperstack::State::Observable
end

require_tree './components'


# require 'opal'
# require 'promise'
# require 'hyper-react'
# if Hyperstack::Component::IsomorphicHelpers.on_opal_client?
#   require 'browser'
#   require 'browser/delay'
# end
# require_tree './components'
