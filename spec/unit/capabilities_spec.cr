require "../spec_helper"

describe Cri::API::CapabilityBroker do
  it "denies by default" do
    broker = Cri::API::CapabilityBroker.deny_all
    request = Cri::API::CapabilityRequest.new("request-1", "tool", "filesystem.read", "/secret", "Read a file")

    broker.authorize(request).should be_false
  end

  it "supports an explicit allow policy for controlled hosts and tests" do
    broker = Cri::API::CapabilityBroker.allow_all
    request = Cri::API::CapabilityRequest.new("request-2", "extension", "ui.notification", "info", "Notify user")

    broker.authorize(request).should be_true
  end

  it "waits for an asynchronous event-backed approval without blocking the scheduler" do
    events = Cri::EventBus.new
    backend = Cri::API::EventApprovalBackend.new(events)
    broker = Cri::API::CapabilityBroker.new(backend)
    request = Cri::API::CapabilityRequest.new("request-3", "tool", "network.request", "https://example.test", "Fetch data")
    requested = Channel(String).new(1)
    completed = Channel(Bool).new(1)

    events.subscribe("approval.requested") do |event|
      requested.send(event.data["id"].as_s)
    end
    spawn { completed.send(broker.authorize(request)) }

    id = requested.receive
    broker.resolve(id, Cri::API::ApprovalDecision::Allow).should be_true
    completed.receive.should be_true
  end
end

describe "default effect approval" do
  it "denies a valid side effect when no approval backend is supplied" do
    grants = Cri::Permissions::GrantPolicy.default
    handler = Cri::Effects::Handler.new(grants.for_extension("fixture"), Cri::Permissions::Request.new)
    result = handler.handle(JSON.parse(%({"type":"ui.notification","message":"hello","level":"info"})))

    result.ok.should be_false
    result.error.should eq("capability approval denied")
  end
end
