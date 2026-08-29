require 'spec_helper'

# Regression coverage for #104: on Rails 6.1.7.x the queued-message `data`
# column dumped fine and then raised on the way back in --
#   Psych::DisallowedClass: Tried to load unspecified class:
#   ActiveSupport::HashWithIndifferentAccess
# -- because the permitted-class list was applied only on Rails >= 7.1 and the
# pre-7.1 branch fell back to a bare `serialize :data`, while 6.1.7 carries the
# same safe-load backport.
#
# Server-side and browser-free, so this runs in seconds. It drives the coder
# directly rather than through a live queued broadcast, because reaching the
# queue in a spec requires winning the transport handshake race that #70 exists
# to remove -- that is exactly why this defect stayed invisible: the only path
# that reads a QueuedMessage back is one that is hard to provoke on purpose.
describe Hyperstack::ConnectionAdapter::ActiveRecord::QueuedMessage do
  let(:coder) { described_class::PermittedYAMLCoder }

  # The shape hyperstack actually queues: a message name plus serialized record
  # params, always a HashWithIndifferentAccess, routinely carrying times.
  let(:payload) do
    ActiveSupport::HashWithIndifferentAccess.new(
      message: 'change',
      data: ActiveSupport::HashWithIndifferentAccess.new(
        model: 'Sample',
        record: { 'id' => 1, 'name' => 'sample2' },
        updated_at: Time.now.utc,
        effective_on: Date.today,
        amount: BigDecimal('1.5'),
        action: :created
      )
    )
  end

  it 'round-trips the payload without raising' do
    expect { coder.load(coder.dump(payload)) }.not_to raise_error
  end

  it 'preserves the classes the payload actually carries' do
    round = coder.load(coder.dump(payload))

    expect(round).to be_a(ActiveSupport::HashWithIndifferentAccess)
    expect(round[:data]).to be_a(ActiveSupport::HashWithIndifferentAccess)
    expect(round[:data][:updated_at]).to be_a(Time)
    expect(round[:data][:effective_on]).to be_a(Date)
    expect(round[:data][:amount]).to be_a(BigDecimal)
    expect(round[:data][:action]).to eq(:created)
    # indifferent access must survive: the transport reads these with strings
    expect(round['data']['model']).to eq('Sample')
  end

  # Guards the guard. If this ever stops raising, Rails has changed its default
  # and the rest of this group would be proving nothing.
  it 'still raises without the permitted classes' do
    expect { YAML.safe_load(coder.dump(payload)) }
      .to raise_error(Psych::DisallowedClass, /HashWithIndifferentAccess/)
  end

  it 'tolerates a repeated value, which Psych emits as an alias' do
    shared = { 'model' => 'Sample' }
    repeated = ActiveSupport::HashWithIndifferentAccess.new(a: shared, b: shared)

    expect { coder.load(coder.dump(repeated)) }.not_to raise_error
  end

  it 'passes nil through in both directions' do
    expect(coder.dump(nil)).to be_nil
    expect(coder.load(nil)).to be_nil
  end

  it 'passes a non-YAML string through rather than raising' do
    expect(coder.load('not yaml')).to eq('not yaml')
  end
end
