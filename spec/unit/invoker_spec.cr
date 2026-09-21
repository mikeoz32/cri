require "../spec_helper"

class FakeRuntime < Cri::Wasm::Runtime
  getter request : Cri::Wasm::RequestEnvelope?

  def call(manifest : Cri::Extensions::Manifest, request : Cri::Wasm::RequestEnvelope) : Cri::Wasm::ResponseEnvelope
    @request = request
    Cri::Wasm::ResponseEnvelope.new(true, JSON.parse(%({"called":true})))
  end
end

describe Cri::Extensions::Invoker do

  it "routes declared contributions through the runtime" do
    manifest = Cri::Extensions::Manifest.load("examples/extensions/fixture/extension.toml")
    runtime = FakeRuntime.new
    response = Cri::Extensions::Invoker.new(runtime).invoke(
      manifest,
      "tool",
      "fixture.echo",
      JSON.parse(%({"number":1}))
    )

    response.ok.should be_true
    runtime.request.not_nil!.name.should eq("fixture.echo")
  end

  it "rejects undeclared contributions" do
    manifest = Cri::Extensions::Manifest.load("examples/extensions/fixture/extension.toml")
    response = Cri::Extensions::Invoker.new(FakeRuntime.new).invoke(
      manifest,
      "tool",
      "missing",
      JSON.parse("{}")
    )

    response.ok.should be_false
  end
end
