require 'spec_helper'

# Regression coverage for #68.
#
# Each `mount` writes the page's payload -- component, params, and the compiled
# client code carrying `isomorphic do` / `before_mount` / `insert_html` blocks --
# into a FileCache under the test URL's id, then asks the browser for that URL.
#
# hyper-model and hyper-operation run their batches as several concurrent rspec
# PROCESSES in one container (the spec:parallel rake task). The cache is rooted
# at a fixed /tmp path and its entry path is MD5(key) alone, so the key is the
# only thing separating one process's payload from another's. While the id was a
# bare counter -- restarting at 1 in every process -- two batches reached the
# same key and the loser's page booted with the winner's client code. Nothing
# about that is visible: the payload is structurally valid, so the page renders,
# it just carries somebody else's code, and whatever the spec defined in an
# `isomorphic do` block is simply absent for the rest of the example.
#
# These examples fork rather than reasoning about the format, because forking is
# what actually reproduces the collision: a child inherits the counter, so
# resetting it to 0 puts every process at "the first mount of the run" at once --
# exactly the state two freshly-spawned batches are in.
describe 'the mount payload cache key' do
  before { skip 'fork is unavailable on this platform' unless Process.respond_to?(:fork) }

  controller = HyperSpec::Internal::Controller

  # Run `block` in a fresh child that believes it is at the start of its own run,
  # and return whatever the child writes back.
  def in_a_child_process
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      HyperSpec::Internal::Controller
        .instance_variable_set(:@_hyperspec_private_test_id, 0)
      writer.write(yield.to_s)
      writer.close
      exit!(0)
    end
    writer.close
    Process.wait(pid)
    reader.read.tap { reader.close }
  end

  # The counter is process-global and the rest of the suite mounts pages, so put
  # it back where it was.
  around do |example|
    saved = controller.instance_variable_get(:@_hyperspec_private_test_id)
    example.run
    controller.instance_variable_set(:@_hyperspec_private_test_id, saved)
  end

  it 'differs between processes that are both on their first mount' do
    controller.instance_variable_set(:@_hyperspec_private_test_id, 0)
    ours = controller.test_id
    theirs = Array.new(3) { in_a_child_process { controller.test_id } }

    # Every id is the first of its own run ...
    expect([ours, *theirs].map { |id| id.to_s[/-(\d+)\z/, 1] }).to eq(%w[1 1 1 1])
    # ... and yet no two of them collide.
    expect([ours, *theirs].uniq.size).to eq(4)
  end

  it 'survives as a URL segment' do
    expect(controller.test_id.to_s).to_not match(%r{[/.?#\s]})
  end

  it 'keeps a concurrent process from overwriting this run\'s payload' do
    controller.instance_variable_set(:@_hyperspec_private_test_id, 0)
    key = "/hyper_spec_test/#{controller.test_id}"
    controller.cache_write(key, ['ours'])

    3.times { in_a_child_process { controller.cache_write("/hyper_spec_test/#{controller.test_id}", ['theirs']) } }

    expect(controller.cache_read(key)).to eq(['ours'])
  end
end
