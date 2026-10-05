module Cri
  class ToolCallFunction
    include JSON::Serializable

    property name : String
    property arguments : String

    def initialize(@name : String, @arguments : String = "{}")
    end
  end

  class ToolCallRecord
    include JSON::Serializable

    property id : String
    property function : ToolCallFunction
    property type : String = "function"

    def initialize(@id : String, @function : ToolCallFunction, @type : String = "function")
    end
  end

  class ToolCall
    getter id : String
    getter name : String
    getter arguments : RawJSON

    def initialize(@id : String, @name : String, @arguments : RawJSON)
    end

    # Compatibility constructor for callers migrating from JSON::Any.
    def initialize(id : String, name : String, arguments : JSON::Any)
      initialize(id, name, RawJSON.from_any(arguments))
    end

    def initialize(pull : JSON::PullParser)
      record = ToolCallRecord.new(pull)
      @id = record.id
      @name = record.function.name
      @arguments = RawJSON.new(record.function.arguments)
    end

    def to_json(json : JSON::Builder) : Nil
      json.object do
        json.field "id", id
        json.field "type", "function"
        json.field "function" do
          json.object do
            json.field "name", name
            json.field "arguments", arguments.raw
          end
        end
      end
    end
  end

  class Message
    include JSON::Serializable

    getter role : String

    @[JSON::Field(emit_null: true)]
    getter content : String?

    getter name : String?
    getter tool_call_id : String?

    @[JSON::Field(ignore_serialize: tool_calls.empty?)]
    getter tool_calls : Array(ToolCall) = [] of ToolCall

    def self.user(content : String) : Message
      UserMessage.new(content).as(Message)
    end

    def self.assistant(content : String?, tool_calls : Array(ToolCall) = [] of ToolCall) : Message
      AssistantMessage.new(content, tool_calls).as(Message)
    end

    def self.tool(call : ToolCall, content : String) : Message
      ToolMessage.new(call.name, call.id, content).as(Message)
    end

    # Compatibility adapter for older callers. Session storage and provider
    # request construction use the typed message directly.
    def to_api_json : JSON::Any
      JSON.parse(to_json)
    end
  end

  class UserMessage < Message
    def initialize(content : String)
      @role = "user"
      @content = content
      @name = nil
      @tool_call_id = nil
      @tool_calls = [] of ToolCall
    end
  end

  class AssistantMessage < Message
    def initialize(content : String?, tool_calls : Array(ToolCall) = [] of ToolCall)
      @role = "assistant"
      @content = content
      @name = nil
      @tool_call_id = nil
      @tool_calls = tool_calls
    end
  end

  class ToolMessage < Message
    def initialize(name : String, tool_call_id : String, content : String)
      @role = "tool"
      @content = content
      @name = name
      @tool_call_id = tool_call_id
      @tool_calls = [] of ToolCall
    end
  end

  class Message
    use_json_discriminator "role", {user: UserMessage, assistant: AssistantMessage, tool: ToolMessage}
  end
end
