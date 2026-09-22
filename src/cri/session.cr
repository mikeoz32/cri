module Cri
  class Session
    getter id : String
    getter messages = [] of Message
    getter current_model : ModelRef?

    def initialize(@id : String = Random::Secure.hex(8), @current_model : ModelRef? = nil)
    end

    def select_model(@current_model : ModelRef)
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
  end
end
