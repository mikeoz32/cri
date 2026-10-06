require "../spec_helper"

describe "typed JSON configuration" do
  it "round-trips model settings and omits unset fields" do
    settings = Cri::ModelSettings.new("high", 0.25, 2048_i64)
    loaded = Cri::ModelSettings.from_json(settings.to_json)

    loaded.reasoning_effort.should eq("high")
    loaded.temperature.should eq(0.25)
    loaded.max_output_tokens.should eq(2048_i64)
    Cri::ModelSettings.new.to_json.should eq("{}")
  end

  it "rejects model settings with a value of the wrong type" do
    expect_raises(JSON::ParseException) do
      Cri::ModelSettings.from_json(%({"temperature":"warm"}))
    end
  end

  it "loads the legacy config key aliases" do
    config = Cri::ConfigFile.from_json(%({"provider_id":"openai","auth_flow_id":"api-key"}))

    (config.provider || config.provider_id).should eq("openai")
    (config.auth_flow || config.auth_flow_id).should eq("api-key")
  end

  it "parses the session envelope with typed settings and dynamic messages" do
    model = Cri::ModelRef.new("provider/model", "provider", "model", "Model title")
    session = Cri::Session.new("session-1", model, Cri::ModelSettings.new("medium"))
    session.user("hello")
    session.set_extension_data("todo", Cri::RawJSON.new(%({"items":[{"text":"ship it","done":false}]})))

    file_record = Cri::SessionFile.from_json(session.to_json)
    file_record.settings.reasoning_effort.should eq("medium")
    file_record.current_model.not_nil!.model.should eq("model")
    loaded = Cri::Session.from_json(session.to_json)
    loaded.id.should eq("session-1")
    loaded.settings.reasoning_effort.should eq("medium")
    loaded.current_model.not_nil!.title.should eq("Model title")
    loaded.messages.last.content.should eq("hello")
    loaded.extension_data("todo").not_nil!.raw.should eq(%({"items":[{"text":"ship it","done":false}]}))
  end

  it "fills model metadata defaults when loading older session records" do
    model = Cri::SessionModelRef.from_json(%({
      "id":"provider/model",
      "provider_id":"provider",
      "model":"model"
    }))

    model.title.should be_nil
    model.api_type.should eq("")
    model.transport_type.should eq("http")
    model.to_model_ref.title.should eq("model")
  end

  it "keeps arbitrary tool arguments as raw JSON and embeds them without parsing" do
    arguments = Cri::RawJSON.new(%({"city":"Lviv","units":["C","F"]}))
    call = Cri::ToolCall.new("call-1", "weather", arguments)
    message = Cri::Message.from_json(Cri::Message.assistant(nil, [call]).to_json)

    message.should be_a(Cri::AssistantMessage)
    message.tool_calls.first.arguments.raw.should eq(arguments.raw)
    message.to_json.should contain(%("arguments":"{\\"city\\":\\"Lviv\\",\\"units\\":[\\"C\\",\\"F\\"]}"))
  end

  it "parses known extension effects into their discriminator variants" do
    envelope = Cri::Wasm::ResponseEnvelope.from_json(%({
      "ok":true,
      "effects":[{"type":"ui.notification","message":"hello","level":"warning"}]
    }))

    effect = envelope.effects.first
    effect.should be_a(Cri::Effects::NotificationEffect)
    effect.as(Cri::Effects::NotificationEffect).level.should eq("warning")

    expect_raises(JSON::SerializableError) do
      Cri::Wasm::ResponseEnvelope.from_json(%({"ok":true,"effects":[{"type":"unknown.effect"}]}))
    end
  end

  it "round-trips WASM tool input without materializing a JSON tree" do
    request = Cri::Wasm::RequestEnvelope.new(
      "tool",
      "example.echo",
      Cri::RawJSON.new(%({"nested":[1,true,null]}))
    )

    loaded = Cri::Wasm::RequestEnvelope.from_json(request.to_json)
    loaded.input.raw.should eq(%({"nested":[1,true,null]}))
  end
end
