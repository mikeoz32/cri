module Cri
  class ToolCall
    getter id : String
    getter name : String
    getter arguments : JSON::Any

    def initialize(@id : String, @name : String, @arguments : JSON::Any)
    end
  end

  class Message
    getter role : String
    getter content : String?
    getter name : String?
    getter tool_call_id : String?
    getter tool_calls : Array(ToolCall)

    def initialize(@role : String, @content : String? = nil, @name : String? = nil, @tool_call_id : String? = nil, @tool_calls : Array(ToolCall) = [] of ToolCall)
    end

    def self.user(content : String) : self
      new("user", content)
    end

    def self.assistant(content : String?, tool_calls : Array(ToolCall) = [] of ToolCall) : self
      new("assistant", content, nil, nil, tool_calls)
    end

    def self.tool(call : ToolCall, content : String) : self
      new("tool", content, call.name, call.id)
    end

    def self.from_json(value : JSON::Any) : Message
      role = value["role"].as_s
      content = value["content"]?.try(&.as_s?)
      name = value["name"]?.try(&.as_s?)
      tool_call_id = value["tool_call_id"]?.try(&.as_s?)
      calls = [] of ToolCall
      value["tool_calls"]?.try(&.as_a).try do |items|
        items.each do |item|
          function = item["function"]?
          call_name = function.try(&.["name"]?.try(&.as_s?)) || item["name"]?.try(&.as_s?) || ""
          raw_arguments = function.try(&.["arguments"]?.try(&.as_s?)) || item["arguments"]?.try(&.as_s?) || "{}"
          call_arguments = JSON.parse(raw_arguments)
          call_id = item["id"]?.try(&.as_s?) || item["call_id"]?.try(&.as_s?) || Random::Secure.hex(8)
          calls << ToolCall.new(call_id, call_name, call_arguments)
        end
      end
      new(role, content, name, tool_call_id, calls)
    end

    def to_api_json : JSON::Any
      JSON.parse(JSON.build do |json|
        json.object do
          json.field "role", role
          json.field "content", content || ""
          json.field "name", name if name
          json.field "tool_call_id", tool_call_id if tool_call_id
          unless tool_calls.empty?
            json.field "tool_calls" do
              json.array do
                tool_calls.each do |call|
                  json.object do
                    json.field "id", call.id
                    json.field "type", "function"
                    json.field "function" do
                      json.object do
                        json.field "name", call.name
                        json.field "arguments", call.arguments.to_json
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end)
    end
  end
end
