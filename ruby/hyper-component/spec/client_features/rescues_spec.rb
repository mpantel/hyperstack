require 'spec_helper'

describe 'rescues macro', js: true do

  before(:each) do
    client_option raise_on_js_errors: :off
  end

  it 'will run the block when an error is raised' do
    mount 'Test' do
      class Test < Hyperloop::Component
        render(DIV) do
          raise 'explosion' unless @some_state
          'FALLBACK'
        end
        rescues do
          @some_state = true
        end
      end
    end
    expect(page).to have_content('FALLBACK')
  end

  it 'recovers from a transient error consumed on the first raise (#39)' do
    # React >= 18 (createRoot, concurrent renderer) recovers from a render error
    # by re-rendering the whole root once (React error #520) BEFORE escalating to
    # the error boundary; it only calls componentDidCatch if that recovery render
    # ALSO throws. A rescue whose trigger clears on the first raise — a transient
    # error, or the `raise_error!` + reset idiom — would therefore be "recovered"
    # and its `rescues` block never run. On React 17's legacy root the throw went
    # straight to the boundary, so this regressed. Component#_render_wrapper
    # re-raises @__hyperstack_pending_render_error on the recovery render so it
    # reaches the boundary. The trigger here is a reactive UPDATE (a click), not a
    # mount, and clears itself on the first raise (`@boom = false` before `raise`).
    #
    # Salvaged from the retired branch lines, where it only ever ran on one React
    # 18 cell. Two cross-cell caveats, unverified until a full-matrix run:
    #   * on React 16/17 the throw reaches the boundary directly, so the fallback
    #     appears for a simpler reason and the example should still pass;
    #   * the recovery re-render is a DEVELOPMENT-build behaviour. The react-rails
    #     cells serve a dev build; the esbuild/npm React 19 cells may serve a
    #     production build, where React does not replay the throwing render.
    mount 'Test' do
      class Test < Hyperloop::Component
        class << self
          attr_accessor :boom
        end
        def check!
          if Test.boom
            Test.boom = false
            raise 'transient'
          end
        end
        render(DIV) do
          check!
          @rescued ? 'FALLBACK' : 'normal'
        end
        rescues { @rescued = true }
      end
    end
    expect(page).to have_content('normal')
    # trigger a reactive UPDATE whose render raises once (Test.boom cleared before
    # the raise), then expect the rescue fallback
    evaluate_ruby { Test.boom = true; Hyperstack::Component.force_update! }
    expect(page).to have_content('FALLBACK')
  end

  it 'will catch specific errors' do
    mount 'Test' do
      class MyError < Exception; end
      class OtherError < Exception; end

      class InnerTest < Hyperloop::Component
        class << self
          attr_accessor :test_failed
        end
        param :dont_fail
        render(DIV) do
          raise MyError unless @DontFail
          'NO FAIL'
        end
        rescues OtherError do
          InnerTest.test_failed = true
        end
      end

      class Test < Hyperloop::Component
        render(DIV) do
          InnerTest(dont_fail: @dont_fail)
        end
        rescues MyError do
          @dont_fail = true
        end
      end
    end
    expect(page).to have_content('NO FAIL')
    expect_evaluate_ruby("InnerTest.test_failed").to be_falsy
  end

  it 'will pass the error to the block' do
    mount 'Test' do
      class MyError < Exception; end
      class Test < Hyperloop::Component
        render(DIV) do
          raise MyError, "error data" unless @err_data
          "FALLBACK #{@err_data}"
        end
        rescues MyError do |err_data|
          @err_data = err_data
        end
      end
    end
    expect(page).to have_content('FALLBACK MyError: error data')
  end

  it 'will catch several error types with the same block' do
    mount 'Test' do
      class MyError < Exception; end
      class OtherError < Exception; end

      class InnerTest < Hyperloop::Component
        param :err_type
        render(DIV) do
          raise Object.const_get(@ErrType) unless @err
          @err
        end
        rescues MyError, OtherError do |err|
          @err = err.to_s
        end
      end

      class Test < Hyperloop::Component
        render(DIV) do
          InnerTest(err_type: 'MyError')
          InnerTest(err_type: 'OtherError')
        end
      end
    end
    expect(page).to have_content('MyError')
    expect(page).to have_content('OtherError')
  end

end
