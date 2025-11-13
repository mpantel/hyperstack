module Hyperstack
  module Legacy
    module Store
      VERSION = File.read(File.expand_path("../../../../../../HYPERSTACK_VERSION", __dir__)).strip
    end
  end
end
