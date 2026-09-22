module Cri
  class Session
    getter id : String
    getter messages = [] of Message
    getter current_model : ModelRef?
    getter settings : ModelSettings

    def initialize(
      @id : String = Random::Secure.hex(8),
      @current_model : ModelRef? = nil,
      @settings : ModelSettings = ModelSettings.new,
    )
    end

    def select_model(@current_model : ModelRef)
    end

    def set_settings(@settings : ModelSettings)
    end

    def add(message : Message)
      messages << message
    end

    def user(content : String)
      add(Message.user(content))
    end

    def clear
      messages.clear
    end

    def api_messages : Array(JSON::Any)
      messages.map(&.to_api_json)
    end

    def to_json_any : JSON::Any
      JSON.parse({
        "id"            => id,
        "current_model" => current_model.try(&.to_json_any),
        "settings"      => settings.to_json_any,
        "messages"      => messages.map(&.to_api_json),
      }.to_json)
    end

    def self.from_json(value : JSON::Any) : Session
      session = new(
        value["id"].as_s,
        value["current_model"]?.try { |model| ModelRef.from_json(model) },
        ModelSettings.from_json(value["settings"]? || JSON.parse("{}"))
      )
      value["messages"]?.try(&.as_a).try do |items|
        items.each { |item| session.add(Message.from_json(item)) }
      end
      session
    end
  end
end
