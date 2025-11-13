module Hyperstack
  module Config
    VERSION = File.read(File.expand_path("../../../../../HYPERSTACK_VERSION", __dir__)).strip.delete("'")
  end
end
