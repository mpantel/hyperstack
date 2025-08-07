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

    size_window(100, 100)
    @min_width = width
    @min_height = height
    size_window(500, 500)
    @height_adjust = 500 - height
    size_window(6000, 6000)
    @max_width = width
    @max_height = height
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
