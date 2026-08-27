require 'spec_helper'

# Regression coverage for #41: wait_for_ajax used to sleep once and then check
# "is anything running?" a *single* time, so a request that started later than
# one poll interval after the action that triggered it (queued behind a
# debounce, a requestAnimationFrame, or a Hyperstack `mutate` that re-renders
# before dispatching the operation) had not begun yet when that check ran.
# Callers that then read state directly -- straight from the DB, with no
# page-content assertion to catch a late update -- got a false "done" and
# observed pre-request state.  The idle state must now hold across
# REQUIRED_IDLE_POLLS consecutive checks before the wait ends.
describe 'HyperSpec::WaitForAjax#wait_for_ajax' do
  # Drives wait_for_ajax off a scripted sequence of finished_all_ajax_requests?
  # answers instead of a browser: one entry per poll, the last entry repeating
  # once the sequence is exhausted.  sleep is replaced by a token real sleep so
  # a never-idle sequence still reaches Timeout without spinning hot.
  let(:waiter_class) do
    Class.new do
      include HyperSpec::WaitForAjax

      attr_reader :polls, :slept

      def initialize(idle_sequence)
        @idle_sequence = idle_sequence.dup
        @polls = 0
        @slept = []
      end

      def finished_all_ajax_requests?
        @polls += 1
        @idle_sequence.size > 1 ? @idle_sequence.shift : @idle_sequence.first
      end

      def sleep(seconds)
        @slept << seconds
        Kernel.sleep 0.001
      end
    end
  end

  def waiter(*idle_sequence)
    waiter_class.new(idle_sequence)
  end

  it 'does not stop at a single idle poll while a request is still to start' do
    # idle, then the late request finally shows up, then idle twice
    subject = waiter(true, false, true, true)
    subject.wait_for_ajax
    expect(subject.polls).to eq(4)
  end

  it 'stops once the idle state holds across consecutive polls' do
    subject = waiter(true, true)
    subject.wait_for_ajax
    expect(subject.polls).to eq(HyperSpec::WaitForAjax::REQUIRED_IDLE_POLLS)
  end

  it 'keeps waiting while requests are running' do
    subject = waiter(false, false, false, true, true)
    subject.wait_for_ajax
    expect(subject.polls).to eq(5)
  end

  it 'restarts the idle count when a request appears mid-run' do
    subject = waiter(true, true, true) # never interrupted: stops at the second
    subject.wait_for_ajax
    expect(subject.polls).to eq(2)
  end

  it 'polls at AJAX_POLL_INTERVAL' do
    subject = waiter(true, true)
    subject.wait_for_ajax
    expect(subject.slept).to eq([HyperSpec::WaitForAjax::AJAX_POLL_INTERVAL] * 2)
  end

  it 'still times out when requests never finish' do
    allow(Capybara).to receive(:default_max_wait_time).and_return(0.2)
    subject = waiter(false)
    expect { subject.wait_for_ajax }.to raise_error(Timeout::Error)
  end

  # The confirmation poll must never make the helper *worse* than the
  # single-check version it replaced. Both cases below are the pre-#41
  # behaviour: it broke on the first idle observation, so anything that has
  # seen idle once must still return rather than raise or hang.
  context 'when the wait budget runs out' do
    it 'returns instead of raising once idle has been seen' do
      # A page that never goes quiet twice in a row -- e.g. a polling transport
      # re-issuing its request -- used to return on the first idle poll.
      allow(Capybara).to receive(:default_max_wait_time).and_return(0.6)
      subject = waiter(true, false, true, false)
      expect { subject.wait_for_ajax }.not_to raise_error
    end

    it 'starts no further poll after the budget is spent' do
      # `running?` swallows the Timeout::Error the enclosing Timeout.timeout
      # raises, and Ruby's Timeout fires only once -- so a confirmation poll
      # issued after the deadline would run entirely unprotected.
      allow(Capybara).to receive(:default_max_wait_time).and_return(0.0)
      subject = waiter(true, true)
      subject.wait_for_ajax
      expect(subject.polls).to eq(1)
    end
  end
end
