module Cri
  # A validated JSON value kept in its encoded form. Use this at open-ended
  # protocol boundaries where the host must forward data without inspecting it.
  struct RawJSON
    getter raw : String

    def initialize(@raw : String)
      validate!(@raw)
    end

    def initialize(pull : JSON::PullParser)
      @raw = pull.read_raw
    end

    def self.new(pull : JSON::PullParser) : self
      new(pull.read_raw)
    end

    def self.from_json(value : String) : self
      new(value)
    end

    def self.from_any(value : JSON::Any) : self
      new(value.to_json)
    end

    def to_json(json : JSON::Builder) : Nil
      json.raw(raw)
    end

    def to_json : String
      raw
    end

    def bytesize : Int32
      raw.bytesize
    end

    private def validate!(value : String) : Nil
      parser = JSON::PullParser.new(value)
      parser.read_raw
      raise ArgumentError.new("trailing data after JSON value") unless parser.kind.eof?
    end
  end
end
