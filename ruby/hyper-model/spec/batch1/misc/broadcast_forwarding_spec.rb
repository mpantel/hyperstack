require 'spec_helper'

# Regression coverage for the hyper-model half of #112.
#
# `Broadcast.after_commit` chooses between running `SendPacket` here and posting
# it to the running server, and it used to make that choice on "is this process
# the one serving requests?". That is the wrong axis -- see
# hyper-operation/spec/hyper-operation/direct_delivery_spec.rb, which covers the
# predicate itself. Here the point is narrower: model change broadcasts must ask
# the *same* question the ServerOp dispatch path asks.
#
# Model broadcasts were never dropped in production the way ServerOp dispatches
# were -- they forward through `SendPacket.remote` -> `execute_remote_api`, which
# is not gated on `Rails.env.development?` -- but a rake task on a shared
# transport was still making an HTTP round trip to get the server to run the
# very operation it could have run itself. Two forwarding paths asking two
# different questions is the asymmetry #112 removes.
#
# Deliberately browser-free: `after_commit` is server-side Ruby, and the branch
# it takes is decided before anything reaches a client.
describe 'ReactiveRecord::Broadcast.after_commit forwarding' do
  # hyper-spec declares `Hyperstack.on_server = true` for every example (the
  # rspec process really is the Capybara server). These examples are about what
  # a console or a rake task does, so it has to be put back.
  around(:each) do |example|
    saved_setting = Hyperstack.on_server
    begin
      example.run
    ensure
      Hyperstack.on_server = saved_setting
    end
  end

  let(:data) { { channel: 'Test', broadcast_id: 'abc' } }

  # A doubled model is enough: everything `after_commit` does with it happens
  # after the branch has already been chosen.
  let(:model) { double('model', __synchromesh_update_time: Time.now) }

  before(:each) do
    # Skip the policy machinery -- which channels a record broadcasts on is a
    # different question, covered elsewhere -- and hand `after_commit` the data
    # it would have produced.
    allow(Hyperstack::InternalPolicy).to receive(:regulate_broadcast).and_yield(data)

    # A console/rake task with a server on file: the shape that used to forward
    # unconditionally.
    Hyperstack.on_server = false
    allow(Hyperstack::Connection).to receive(:root_path).and_return('http://example.com/')
  end

  it 'runs the packet here when this process can deliver directly' do
    allow(Hyperstack).to receive(:direct_delivery?).and_return(true)

    expect(ReactiveRecord::Broadcast).not_to receive(:send_to_server)
    expect(ReactiveRecord::Broadcast::SendPacket)
      .to receive(:run).and_return(double('op', error: nil))

    ReactiveRecord::Broadcast.after_commit(:change, model)
  end

  it 'still forwards when this process cannot deliver directly' do
    allow(Hyperstack).to receive(:direct_delivery?).and_return(false)

    expect(ReactiveRecord::Broadcast::SendPacket).not_to receive(:run)
    expect(ReactiveRecord::Broadcast).to receive(:send_to_server)

    ReactiveRecord::Broadcast.after_commit(:change, model)
  end

  it 'never forwards from the server itself, whatever the transport' do
    Hyperstack.on_server = true
    allow(Hyperstack).to receive(:direct_delivery?).and_return(false)

    expect(ReactiveRecord::Broadcast).not_to receive(:send_to_server)
    expect(ReactiveRecord::Broadcast::SendPacket)
      .to receive(:run).and_return(double('op', error: nil))

    ReactiveRecord::Broadcast.after_commit(:change, model)
  end
end
