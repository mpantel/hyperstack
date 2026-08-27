# Stream output live instead of dumping it when the process exits. Ruby's own IO
# buffering (not glibc's, so `stdbuf` has NO effect here) holds output until ~8KB
# or exit whenever stdout is not a tty -- true of every CI job, which is why a
# progressing run can look hung for minutes. (#69)
$stdout.sync = true
$stderr.sync = true

require 'hyper-spec'
require 'pry'

ENV["RAILS_ENV"] ||= 'test'
require File.expand_path('../test_app/config/environment', __FILE__)

require 'rspec/rails'
require 'rspec-steps'
require 'timecop'
# require 'mini_racer'

module Helpers
  def computed_style(selector, prop)
    page.evaluate_script(
      "window.getComputedStyle(document.querySelector('#{selector}'))['#{prop}']"
    )
  end

  def calculate_window_restrictions
    return if @min_width

    probe_window(100, 100)
    @min_width = width
    @min_height = height
    probe_window(500, 500)
    @height_adjust = 500 - height
    probe_window(6000, 6000)
    @max_width = width
    @max_height = height
  end

  # 100x100 and 6000x6000 are sizes we expect the browser to refuse -- finding
  # out where it draws the line is the whole point of the helper above. Go
  # through the internal resize rather than size_window, so #77's reporting
  # stays quiet about a discrepancy this helper provokes on purpose.
  def probe_window(width, height)
    hs_internal_resize_to(*determine_size(width, height))
  end

  def height
    evaluate_script('window.innerHeight')
  end

  def width
    evaluate_script('window.innerWidth')
  end

  def dims
    [width, height]
  end

  def adjusted(width, height)
    [
      [@max_width, [width, @min_width].max].min,
      [@max_height, [height - @height_adjust, @min_height].max].min
    ]
  end

  def expected_dims(width, height)
    # This accounts for both debugger width and browser constraints
    # similar to determine_size + window adjustments
    adjusted_dims = adjusted(width, height)
    # Add the debugger width like determine_size does
    # Use the same calculation as window_sizing.rb
    debugger_w = calculate_debugger_width
    [adjusted_dims[0] + debugger_w, adjusted_dims[1]]
  end

  def calculate_debugger_width
    # Use the actual debugger width calculated during window restrictions setup
    # This matches the logic in window_sizing.rb
    return @debugger_width if @debugger_width
    
    # If not calculated yet, get current width and subtract window.innerWidth
    # to find the chrome/debugger width
    current_outer_width = page.evaluate_script('window.outerWidth')
    current_inner_width = page.evaluate_script('window.innerWidth')
    @debugger_width = current_outer_width - current_inner_width
    @debugger_width
  end
end

RSpec.configure do |config|
  config.include Helpers
  # config.after :each do
  #   Rails.cache.clear
  # end

  # config.before :suite do
  #   MiniRacer_Backup = MiniRacer
  #   Object.send(:remove_const, :MiniRacer)
  # end

  # config.around(:each, :prerendering_on) do |example|
  #   MiniRacer = MiniRacer_Backup
  #   example.run
  #   Object.send(:remove_const, :MiniRacer)
  # end
end
