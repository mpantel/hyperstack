# Import the hot-reloader client into the test bundle so the browser spec can
# verify that importing 'hyperstack/hotloader' auto-connects to the hot-loader
# server (see spec/hotloader_client_spec.rb). In a real app this line is added
# by the installer, guarded by `if Rails.env.development?`.
Hyperstack.import 'hyperstack/hotloader', client_only: true
