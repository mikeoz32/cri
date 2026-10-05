module Cri
  class SessionModelRef
    include JSON::Serializable

    property id : String
    property provider_id : String
    property model : String
    property title : String?
    property auth_flow_id : String?
    property api_type : String? = ""
    property endpoint : String?

    @[JSON::Field(key: "transport")]
    property transport_type : String? = "http"

    def initialize(
      @id : String,
      @provider_id : String,
      @model : String,
      @title : String? = nil,
      @auth_flow_id : String? = nil,
      @api_type : String? = "",
      @endpoint : String? = nil,
      @transport_type : String? = "http",
    )
    end

    def self.from_model(ref : ModelRef) : self
      new(ref.id, ref.provider_id, ref.model, ref.title, ref.auth_flow_id, ref.api_type, ref.endpoint, ref.transport_type)
    end

    def to_model_ref : ModelRef
      ModelRef.new(id, provider_id, model, title || model, auth_flow_id, api_type || "", endpoint, transport_type || "http")
    end
  end

  class SessionFile
    include JSON::Serializable

    property id : String
    property current_model : SessionModelRef?
    property settings : ModelSettings = ModelSettings.new
    property messages : Array(Message) = [] of Message

    def initialize(
      @id : String,
      @current_model : SessionModelRef? = nil,
      @settings : ModelSettings = ModelSettings.new,
      @messages : Array(Message) = [] of Message,
    )
    end
  end

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

    def api_messages : Array(Message)
      messages
    end

    def to_json : String
      SessionFile.new(
        id,
        current_model.try { |model| SessionModelRef.from_model(model) },
        settings,
        messages
      ).to_json
    end

    def to_json_any : JSON::Any
      json = to_json
      JSON.parse(json)
    end

    def self.from_json(value : JSON::Any) : Session
      from_json(value.to_json)
    end

    def self.from_json(json : String) : Session
      record = SessionFile.from_json(json)
      session = new(
        record.id,
        record.current_model.try(&.to_model_ref),
        record.settings
      )
      record.messages.each { |item| session.add(item) }
      session
    end
  end
end
