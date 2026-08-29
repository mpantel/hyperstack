require "spec_helper"

describe "rails-hyperstack" do
  it "builds a working app", js: true do
    visit "/"
    expect(page).to have_content("App")
  end

  it "installs hyper-model and friends", js: true do
    visit "/"
    expect do
      Hyperstack::Model.load { Sample.count }
    end.on_client_to eq(0)
    on_client do
      Sample.create(name: "sample1", description: "the first sample")
    end
    wait_for_ajax
    expect(Sample.count).to eq(1)
    expect(Sample.first.name).to eq("sample1")
    expect(Sample.first.description).to eq("the first sample")
    # No reload: this is the real reactive-push assertion. The create is
    # broadcast back over the app's transport and invalidates the `Sample.count`
    # scope the client cached above, and `on_client_to` re-evaluates until
    # the matcher agrees or Capybara's timeout expires (#64) -- so it waits for
    # the push rather than racing it.
    #
    # This used to be `page.refresh` plus a one-shot read, which only proved the
    # create round-tripped to the server. Two things had to change first: that
    # one-shot read became a polling one (#64), and queued broadcasts stopped
    # raising Psych::DisallowedClass on Rails 7.1+ (see QueuedMessage's
    # PERMITTED_YAML_CLASSES) -- the latter is what actually made the push
    # undeliverable on CI while it worked on a fast local run. (#44, was #20)
    expect { Hyperstack::Model.load { Sample.count } }.on_client_to eq(1)
  end

  # The direction the queued path breaks first: nothing the client did primes
  # it, so the server's broadcast is all that can make the count move.
  it "pushes a server-side create to the client", js: true do
    visit "/"
    expect do
      Hyperstack::Model.load { Sample.count }
    end.on_client_to eq(0)
    Sample.create(name: "sample2", description: "created on the server")
    expect { Hyperstack::Model.load { Sample.count } }.on_client_to eq(1)
  end

  # #105. The example above is what a broken `on_server?` breaks, but every
  # suite hides it: hyper-spec forces `Hyperstack.on_server = true` in a
  # before(:each), because the predicate used to be `defined?(Rails::Server)`
  # and nothing but `rails server` satisfies that -- not Capybara's in-process
  # puma, and not a Passenger or `bundle exec puma` deployment either. This is
  # a generated app booted the way a real one is, so it is the place to take the
  # override away and make the predicate answer for itself.
  #
  # Rails::Server goes with it: Rails 8's boot path defines it where 6.1 and 7.2
  # do not (#103), and the whole point is that neither answer says anything about
  # whether this process is serving.
  it "knows it is the server without having been started by `rails server`", js: true do
    rails_server = Rails.const_defined?(:Server, false) && Rails.send(:remove_const, :Server)

    # A freshly booted server: nothing declared, nothing observed.
    Hyperstack.on_server = nil
    Hyperstack.instance_variable_set(:@serving_requests, nil)
    expect(Hyperstack.on_server?).to be false

    visit "/"

    # One request through the app's middleware stack is all it takes, and it is
    # the same fact under puma, Passenger or rackup.
    expect(Hyperstack.on_server?).to be true
  ensure
    Rails.const_set(:Server, rails_server) if rails_server
  end

  it "implements server_side_auto_require", js: true do
    expect(Sample.super_secret_server_side_method).to be true
    expect do
      Sample.respond_to? :super_secret_server_side_method
    end.on_client_to be_falsy
  end
end
