module Cri
  class Agent
    MAX_STEPS               = 16
    MAX_INPUT_BYTES         = 256_i64 * 1024_i64
    MAX_TOOL_CALLS_PER_STEP = 8
    MAX_TOOL_ARGUMENT_BYTES = 256_i64 * 1024_i64
    MAX_TOOL_RESULT_BYTES   = 1_i64 * 1024_i64 * 1024_i64
    MAX_RESPONSE_BYTES      = 4_i64 * 1024_i64 * 1024_i64

    class LimitError < Exception
    end

    getter session : Session
    getter provider : Provider
    getter tools : ToolExecutor
    getter events : EventBus
    getter max_steps : Int32
    getter max_input_bytes : Int64
    getter max_tool_calls_per_step : Int32
    getter max_tool_argument_bytes : Int64
    getter max_tool_result_bytes : Int64
    getter max_response_bytes : Int64

    def initialize(
      @provider : Provider,
      @tools : ToolExecutor,
      @events : EventBus = EventBus.new,
      @session : Session = Session.new,
      @max_steps : Int32 = MAX_STEPS,
      @max_input_bytes : Int64 = MAX_INPUT_BYTES,
      @max_tool_calls_per_step : Int32 = MAX_TOOL_CALLS_PER_STEP,
      @max_tool_argument_bytes : Int64 = MAX_TOOL_ARGUMENT_BYTES,
      @max_tool_result_bytes : Int64 = MAX_TOOL_RESULT_BYTES,
      @max_response_bytes : Int64 = MAX_RESPONSE_BYTES,
    )
      raise ArgumentError.new("max_steps must be positive") unless max_steps > 0
      raise ArgumentError.new("max_tool_calls_per_step must be positive") unless max_tool_calls_per_step > 0
    end

    def run_turn(input : String) : String
      run_turn(input) { |_chunk| }
    end

    def run_turn(input : String, &on_text : String -> Nil) : String
      raise LimitError.new("agent input exceeds #{max_input_bytes} bytes") if input.bytesize > max_input_bytes

      session.user(input)
      events.emit(Event.new("message.user", JSON.parse({"content" => input}.to_json)))

      step = 0
      loop do
        step += 1
        raise "agent step limit exceeded" if step > max_steps

        streamed_bytes = 0_i64
        response = if provider.supports_streaming?
                     provider.complete_stream(session.messages, tools.specs) do |chunk|
                       streamed_bytes += chunk.bytesize
                       raise LimitError.new("agent response exceeds #{max_response_bytes} bytes") if streamed_bytes > max_response_bytes
                       on_text.call(chunk)
                     end
                   else
                     provider.complete(session.messages, tools.specs)
                   end
        response_bytes = response.content.try(&.bytesize) || 0
        raise LimitError.new("agent response exceeds #{max_response_bytes} bytes") if response_bytes > max_response_bytes
        raise LimitError.new("too many tool calls in one response") if response.tool_calls.size > max_tool_calls_per_step
        response.tool_calls.each do |call|
          raise LimitError.new("tool name is empty") if call.name.empty?
          raise LimitError.new("tool arguments exceed #{max_tool_argument_bytes} bytes") if call.arguments.to_json.bytesize > max_tool_argument_bytes
        end

        session.add(Message.assistant(response.content, response.tool_calls))
        events.emit(Event.new("message.assistant", JSON.parse({
          "content"    => response.content,
          "tool_calls" => response.tool_calls.map { |call| call.name },
        }.to_json)))

        return response.content || "" if response.tool_calls.empty?

        response.tool_calls.each do |call|
          result = tools.call(call.name, call.arguments)
          content = result.to_json
          raise LimitError.new("tool result exceeds #{max_tool_result_bytes} bytes") if content.bytesize > max_tool_result_bytes
          session.add(Message.tool(call, content))
          events.emit(Event.new("tool.completed", JSON.parse({
            "name" => call.name,
            "ok"   => result.ok,
          }.to_json)))
        end
      end
    end
  end
end
