require 'spec_helper'

# Regression coverage for the teardown cascade: when Chrome dies mid-run, the
# session is gone before the next `Capybara.reset_sessions!`, which then raised
# InvalidSessionIdError from an `after` hook -- failing the current example AND
# every example after it in the same process. One crash was reported as a whole
# batch of failures (observed: 155 examples / 122 failures, 30 examples / 29
# failures).
#
# Browser-free and fast: it drives HyperSpec.reset_sessions! directly with a
# stubbed Capybara, because the thing under test is the error handling, not the
# browser. Provoking a real Chrome crash on demand is exactly the thing we
# cannot do reliably -- which is why this went unnoticed.
describe 'dead browser session recovery' do
  let(:pool) { { default: :a_session } }

  # The stub MUST be torn down inside the example, not in an `around` hook.
  #
  # Capybara registers its own `append_after` that calls `Capybara.reset_sessions!`,
  # which runs AFTER the example body but BEFORE an `around` hook regains control.
  # With a stub that raises still installed, that teardown raised the stubbed
  # error outside any `expect { }` and failed the example even though the
  # expectation itself had passed -- which is exactly how the first version of
  # this spec failed on all ten cells, while the fix underneath it was working.
  #
  # `ensure` restores before the example returns, so Capybara's teardown always
  # sees the real method.
  def with_reset_raising(error)
    original = Capybara.method(:old_reset_sessions!)
    Capybara.singleton_class.send(:define_method, :old_reset_sessions!) { raise error }
    yield
  ensure
    Capybara.singleton_class.send(:define_method, :old_reset_sessions!, original)
  end

  def with_reset_succeeding
    original = Capybara.method(:old_reset_sessions!)
    Capybara.singleton_class.send(:define_method, :old_reset_sessions!) { :ok }
    yield
  ensure
    Capybara.singleton_class.send(:define_method, :old_reset_sessions!, original)
  end

  before { allow(Capybara).to receive(:send).with(:session_pool).and_return(pool) }

  it 'resets normally when the session is alive' do
    with_reset_succeeding do
      expect { HyperSpec.reset_sessions! }.not_to raise_error
      expect(pool).not_to be_empty
    end
  end

  # The bug itself.
  it 'survives a session that is already gone' do
    with_reset_raising(Selenium::WebDriver::Error::InvalidSessionIdError.new('invalid session id')) do
      expect { HyperSpec.reset_sessions! }.not_to raise_error
    end
  end

  it 'drops the dead session so the next example gets a fresh browser' do
    with_reset_raising(Selenium::WebDriver::Error::InvalidSessionIdError.new('invalid session id')) do
      HyperSpec.reset_sessions!
      expect(pool).to be_empty
    end
  end

  it 'survives chromedriver itself having died' do
    [EOFError.new('end of file reached'), Errno::ECONNREFUSED.new].each do |err|
      with_reset_raising(err) do
        expect { HyperSpec.reset_sessions! }.not_to raise_error
      end
    end
  end

  # Guards the guard. The permitted list is deliberately short: a blanket
  # `rescue StandardError` here would swallow real driver faults, which is the
  # mistake #77 documented in this same file.
  it 'still propagates an unrelated error' do
    with_reset_raising(ArgumentError.new('a genuine bug')) do
      expect { HyperSpec.reset_sessions! }.to raise_error(ArgumentError, /genuine bug/)
    end
  end

  it 'still propagates a WebDriverError that does not mean the session is gone' do
    with_reset_raising(Selenium::WebDriver::Error::WebDriverError.new('something else')) do
      expect { HyperSpec.reset_sessions! }.to raise_error(Selenium::WebDriver::Error::WebDriverError)
    end
  end

  # Recovery runs inside an `after` hook, where raising would be worse than the
  # problem it fixes.
  it 'never raises even if the session pool cannot be cleared' do
    allow(Capybara).to receive(:send).with(:session_pool).and_return(Object.new)
    with_reset_raising(Selenium::WebDriver::Error::InvalidSessionIdError.new('invalid session id')) do
      expect { HyperSpec.reset_sessions! }.not_to raise_error
    end
  end
end
