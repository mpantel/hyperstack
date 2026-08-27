require 'spec_helper'

# Regression coverage for #68.
#
# js examples are retried (hyper-spec.rb sets `example.run_with_retry(retry: 3)`),
# and rspec-retry re-runs a failed example in the SAME example-group instance --
# it calls `ex.run` again, it does not build a new instance. Instance variables
# therefore survive the attempt that failed.
#
# Both mount buffers are consumed by mounting: add_block_with_helpers nils
# @_hyperspec_private_client_code once it has compiled it into a page, and
# send_params_to_controller_via_cache nils @_hyperspec_private_html_block. So
# before this was fixed, the second and third attempts mounted a page WITHOUT
# them, and everything the spec had put there -- `isomorphic do`, `before_mount`,
# `insert_html` -- was silently gone from the client.
#
# What that looked like in CI was the whole problem: the reported failure is the
# LAST attempt's, so a spec that failed once for any transient reason then failed
# for good with "uninitialized constant <SomeModel>", and the first attempt's real
# failure never appeared.
#
# These examples fail their first attempt on purpose and assert that what
# before(:all) put on the client is still there on the retry.
describe 'a retried example', js: true do
  before(:all) do
    insert_html "<div id='inserted-before-all'>hello</div>"

    isomorphic do
      class SurvivesARetry
        def self.hello
          'still here'
        end
      end
    end
  end


  # rspec-retry keeps the instance, so a plain ivar counts the attempts.
  def attempt
    @attempt = (@attempt || 0) + 1
  end

  it 'still has the isomorphic code from before(:all) on the second attempt' do
    this_attempt = attempt
    expect(evaluate_ruby('SurvivesARetry.hello')).to eq('still here')
    raise 'deliberate first-attempt failure -- the retry is the assertion' if this_attempt == 1
  end

  it 'still has the html inserted by before(:all) on the second attempt' do
    this_attempt = attempt
    mount
    expect(page).to have_css('#inserted-before-all')
    raise 'deliberate first-attempt failure -- the retry is the assertion' if this_attempt == 1
  end
end
