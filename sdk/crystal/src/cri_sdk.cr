require "json"
require "./cri_sdk/effects"

module CriSDK
  ABI_VERSION = "cri.extension.v1"

  class Context
    getter session_id : String?
    getter cwd : String
    getter tui : Bool

    def initialize(@cwd : String = "/", @session_id : String? = nil, @tui : Bool = false)
    end
  end

  class Request
    getter abi : String
    getter kind : String
    getter name : String
    getter input : JSON::Any
    getter context : Context

    def initialize(@kind : String, @name : String, @input : JSON::Any, @context : Context = Context.new, @abi : String = ABI_VERSION)
    end

    def self.from_json(source : String) : self
      root = JSON.parse(source)
      context = root["context"]?
      context_value = if context
                        Context.new(
                          context["cwd"]?.try(&.as_s) || "/",
                          context["session_id"]?.try(&.as_s?),
                          context["tui"]?.try(&.as_bool) || false
                        )
                      else
                        Context.new
                      end
      new(root["kind"].as_s, root["name"].as_s, root["input"], context_value, root["abi"].as_s)
    end
  end

  class Response
    include JSON::Serializable

    property ok : Bool
    property result : JSON::Any?
    property effects : Array(JSON::Any)
    property error : String?

    def initialize(@ok : Bool = true, @result : JSON::Any? = nil, @effects = [] of JSON::Any, @error : String? = nil)
    end

    def self.success(result : JSON::Any? = nil, effects : Array(JSON::Any) = [] of JSON::Any) : self
      new(true, result, effects)
    end

    def self.failure(message : String) : self
      new(false, nil, [] of JSON::Any, message)
    end
  end

  abstract class Extension
    abstract def call(request : Request) : Response

    def resume(request : Request, results : Array(JSON::Any)) : Response
      Response.failure("extension does not implement resume")
    end
  end

  class Runtime
    @@extension : Extension? = nil
    @@result_pointer : Int32 = 0_i32
    @@result_length : Int32 = 0_i32

    def self.extension=(extension : Extension)
      @@extension = extension
    end

    def self.alloc(size : Int32) : Int32
      return 0_i32 if size < 0
      Pointer(UInt8).malloc(size).address.to_i32
    end

    def self.free(pointer : Int32, size : Int32)
      LibC.free(Pointer(Void).new(pointer.to_u64)) unless pointer == 0
    end

    def self.call(input_pointer : Int32, input_length : Int32) : Int32
      invoke(input_pointer, input_length, false)
    end

    def self.resume(input_pointer : Int32, input_length : Int32) : Int32
      invoke(input_pointer, input_length, true)
    end

    def self.result_len : Int32
      @@result_length
    end

    def self.free_result(pointer : Int32, size : Int32)
      free(pointer, size)
      @@result_pointer = 0_i32
      @@result_length = 0_i32
    end

    private def self.invoke(input_pointer : Int32, input_length : Int32, resume : Bool) : Int32
      extension = @@extension
      return write_response(Response.failure("SDK extension is not registered")) unless extension

      request = Request.from_json(String.new(Pointer(UInt8).new(input_pointer.to_u64), input_length))
      response = if resume
                   results = request.input["results"].as_a
                   extension.resume(request, results)
                 else
                   extension.call(request)
                 end
      write_response(response)
    rescue ex
      write_response(Response.failure(ex.message || ex.class.name))
    end

    private def self.write_response(response : Response) : Int32
      source = response.to_json
      pointer = alloc(source.bytesize)
      source.to_slice.each_with_index { |byte, index| (Pointer(UInt8).new(pointer.to_u64) + index)[0] = byte }
      @@result_pointer = pointer
      @@result_length = source.bytesize.to_i32
      pointer
    end
  end
end
