require "../spec_helper"
require "file_utils"

describe Cri::SessionStore do
  it "persists the conversation, selected model, and model settings in the workspace" do
    workspace = File.join(Dir.tempdir, "cri-session-#{Random::Secure.hex(4)}")
    Dir.mkdir_p(workspace)
    store = Cri::SessionStore.new(workspace)
    model = Cri::ModelRef.new(
      "extension/openai/openai/chatgpt-device/gpt-5.6-luna",
      "extension/openai/openai",
      "gpt-5.6-luna",
      "GPT-5.6 Luna",
      "chatgpt-device",
      "openai-codex-responses",
      "https://chatgpt.com/backend-api/codex/responses",
      "http+sse"
    )
    session = Cri::Session.new("0123456789abcdef", model, Cri::ModelSettings.new("high"))
    session.user("remember this")
    store.save(session)

    loaded = store.current.not_nil!
    loaded.id.should eq(session.id)
    loaded.current_model.not_nil!.model.should eq("gpt-5.6-luna")
    loaded.current_model.not_nil!.auth_flow_id.should eq("chatgpt-device")
    loaded.settings.reasoning_effort.should eq("high")
    loaded.messages.last.content.should eq("remember this")
  ensure
    FileUtils.rm_rf(workspace) if workspace
  end
end
