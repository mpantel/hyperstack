require 'spec_helper'

# Regression coverage for #71.
#
# `isomorphic do`, `before_mount` / `on_client`, `insert_html` and `add_class`
# inject code into the page at MOUNT time. Mounting used to drain the buffer that
# held it, so the code reached exactly one page -- and anything that replaced that
# page mid-example produced a page with none of it. Every constant, method and
# module the spec had put on the client was then gone for the rest of the run,
# surfacing as `uninitialized constant X` / `undefined method 'y'`.
#
# A page gets replaced more often than it looks. `load_page` / `reload_page` is
# explicit, but insure_page_loaded also reloads on its own whenever
# `evaluate_script('Opal && true')` comes back falsy -- and a transient WebDriver
# failure is swallowed into that same signal, so a hiccup is enough. That is what
# made this intermittent, and it is why it had already been worked around twice by
# hand: 7c3e545ba in hyper-operation's execution_spec, and the header comment in
# hyper-model's batch2/alias_attribute_spec.
#
# Mounting now moves the pending buffer into a mounted buffer that is replayed
# into every page built afterwards, so these assert the injected code is still
# there after the page has been replaced.
describe 'a page re-mounted mid-example', js: true do
  context 'with code injected before the first mount' do
    before(:each) do
      before_mount do
        module SurvivesARemount
          def self.hello
            'still here'
          end
        end
      end
      insert_html "<div id='survives-a-remount'>hello</div>"
    end

    it 'still has the injected code and html after reload_page' do
      expect(evaluate_ruby('SurvivesARemount.hello')).to eq('still here')
      expect(page).to have_css('#survives-a-remount')

      reload_page

      expect(evaluate_ruby('SurvivesARemount.hello')).to eq('still here')
      expect(page).to have_css('#survives-a-remount')
    end

    it 'still has it after the reload insure_page_loaded performs on its own' do
      expect(evaluate_ruby('SurvivesARemount.hello')).to eq('still here')

      # Exactly what a transient `evaluate_script` failure looks like to
      # insure_page_loaded: it probes for Opal, sees none, and reloads.
      page.driver.browser.navigate.to('about:blank')

      expect(evaluate_ruby('SurvivesARemount.hello')).to eq('still here')
    end
  end

  context 'with isomorphic code injected while the page is already mounted' do
    it 'replays it into a page mounted later' do
      # first mount -- from here on isomorphic takes its evaluate-now branch
      expect(evaluate_ruby('1 + 1')).to eq(2)

      isomorphic do
        module InjectedAfterMounting
          def self.hello
            'still here'
          end
        end
        # a module definition is not a usable expression once the promise wrapper
        # wraps it -- the same reason hyper_spec.rb's isomorphic example ends in nil
        nil
      end
      expect(evaluate_ruby('InjectedAfterMounting.hello')).to eq('still here')

      reload_page

      expect(evaluate_ruby('InjectedAfterMounting.hello')).to eq('still here')
    end
  end
end
