require "../src/cri_sdk"
require "../src/cri_sdk_exports"

class HelloExtension < CriSDK::Extension
  def call(request : CriSDK::Request) : CriSDK::Response
    case request.kind
    when "tool"
      text = request.input["text"]?.try(&.as_s) || "hello from Crystal"
      CriSDK::Response.success(JSON.parse({"text" => text}.to_json))
    else
      CriSDK::Response.failure("unsupported request kind: #{request.kind}")
    end
  end

  def resume(request : CriSDK::Request, results : Array(JSON::Any)) : CriSDK::Response
    CriSDK::Response.success(JSON.parse({"results_received" => results.size}.to_json))
  end
end

CriSDK::Runtime.extension = HelloExtension.new
