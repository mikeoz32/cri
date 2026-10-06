require "../spec_helper"
require "file_utils"

class ContextPipelineRuntime < Cri::Wasm::Runtime
  getter calls = [] of String

  def call(manifest : Cri::Extensions::Manifest, request : Cri::Wasm::RequestEnvelope) : Cri::Wasm::ResponseEnvelope
    @calls << request.name
    patch = case request.name
            when "todo.context"
              Cri::Extensions::ContextPatch.new(
                [Cri::Extensions::ContextBlockInput.new("active", "Open todo: ship it")],
                [] of String
              )
            when "filter.context"
              Cri::Extensions::ContextPatch.new(
                [Cri::Extensions::ContextBlockInput.new("note", "Keep this context")],
                ["extension/todo_ext/active"]
              )
            else
              Cri::Extensions::ContextPatch.new
            end
    Cri::Wasm::ResponseEnvelope.new(true, Cri::RawJSON.new(patch.to_json))
  end
end

class ContextCapturingProvider < Cri::Provider
  getter received : Array(Cri::Message)?

  def complete(messages : Array(Cri::Message), tools : Array(Cri::ToolSpec)) : Cri::AssistantResponse
    @received = messages.dup
    Cri::AssistantResponse.new("done")
  end
end

describe Cri::Extensions::ContextPipeline do
  it "runs granted context providers in order and applies additions and removals" do
    root = File.join(Dir.tempdir, "cri-context-#{Random::Secure.hex(4)}")
    Dir.mkdir_p(root)
    todo = write_context_extension(root, "todo_ext", "todo.context")
    filter = write_context_extension(root, "filter_ext", "filter.context")
    begin
      registry = Cri::Extensions::Registry.new([root])
      registry.manifests.concat([todo, filter])
      policy = Cri::Permissions::GrantPolicy.new
      policy.extensions["todo_ext"] = Cri::Permissions::GrantSet.new(context: true)
      policy.extensions["filter_ext"] = Cri::Permissions::GrantSet.new(context: true)
      broker = Cri::API::CapabilityBroker.allow_all
      runtime = ContextPipelineRuntime.new
      events = Cri::EventBus.new
      invoker = Cri::Extensions::Invoker.new(runtime, policy, broker, root, events)
      pipeline = Cri::Extensions::ContextPipeline.new(registry, invoker, policy, broker, events)
      session = Cri::Session.new("session-1")
      session.user("Please finish my plan")

      result = pipeline.messages_for(session, [] of Cri::ToolSpec)

      result.map(&.role).should eq(["system", "user"])
      result.first.content.should eq("Keep this context")
      result.last.content.should eq("Please finish my plan")
      runtime.calls.should eq(["todo.context", "filter.context"])
      session.messages.size.should eq(1)
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "does not expose conversation context without both declaration and grant" do
    root = File.join(Dir.tempdir, "cri-context-#{Random::Secure.hex(4)}")
    Dir.mkdir_p(root)
    manifest = write_context_extension(root, "todo_ext", "todo.context")
    begin
      registry = Cri::Extensions::Registry.new([root])
      registry.manifests << manifest
      policy = Cri::Permissions::GrantPolicy.new
      policy.extensions["todo_ext"] = Cri::Permissions::GrantSet.default_dev
      broker = Cri::API::CapabilityBroker.allow_all
      runtime = ContextPipelineRuntime.new
      invoker = Cri::Extensions::Invoker.new(runtime, policy, broker, root)
      pipeline = Cri::Extensions::ContextPipeline.new(registry, invoker, policy, broker, Cri::EventBus.new)
      session = Cri::Session.new("session-1")
      session.user("private prompt")

      result = pipeline.messages_for(session, [] of Cri::ToolSpec)

      result.should eq(session.messages)
      runtime.calls.should be_empty
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "injects context blocks only into the request and never into the session transcript" do
    root = File.join(Dir.tempdir, "cri-context-#{Random::Secure.hex(4)}")
    Dir.mkdir_p(root)
    manifest = write_context_extension(root, "todo_ext", "todo.context")
    begin
      registry = Cri::Extensions::Registry.new([root])
      registry.manifests << manifest
      policy = Cri::Permissions::GrantPolicy.new
      policy.extensions["todo_ext"] = Cri::Permissions::GrantSet.new(context: true)
      broker = Cri::API::CapabilityBroker.allow_all
      runtime = ContextPipelineRuntime.new
      events = Cri::EventBus.new
      invoker = Cri::Extensions::Invoker.new(runtime, policy, broker, root, events)
      pipeline = Cri::Extensions::ContextPipeline.new(registry, invoker, policy, broker, events)
      session = Cri::Session.new("session-1")
      provider = ContextCapturingProvider.new
      agent = Cri::Agent.new(provider, Cri::ToolRegistry.new, session: session, context_pipeline: pipeline)

      agent.run_turn("Continue")

      provider.received.not_nil!.first.role.should eq("system")
      provider.received.not_nil!.first.content.should eq("Open todo: ship it")
      session.messages.map(&.role).should eq(["user", "assistant"])
      runtime.calls.should eq(["todo.context"])
    ensure
      FileUtils.rm_rf(root)
    end
  end
end

private def write_context_extension(root : String, name : String, contribution : String) : Cri::Extensions::Manifest
  path = File.join(root, name)
  Dir.mkdir_p(path)
  manifest_path = File.join(path, "extension.toml")
  File.write(manifest_path, <<-TOML
    name = "#{name}"
    version = "0.1.0"
    abi = "cri.extension.v1"
    wasm = "plugin.wasm"

    [permissions]
    context = true

    [[context_providers]]
    name = "#{contribution}"
    entrypoint = "cri_call"
    TOML
  )
  Cri::Extensions::Manifest.load(manifest_path, require_wasm: false)
end
