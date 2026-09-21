require "spec"
require "../src/cri_sdk"
require "../src/cri_sdk_exports"

class SDKTestExtension < CriSDK::Extension
  def call(request : CriSDK::Request) : CriSDK::Response
    CriSDK::Response.success(JSON.parse({
      "kind" => request.kind,
      "name" => request.name,
    }.to_json))
  end
end

describe CriSDK do
  it "hides the request protocol behind Extension and Request" do
    extension = SDKTestExtension.new
    request = CriSDK::Request.from_json(%({"abi":"cri.extension.v1","kind":"tool","name":"test","input":{},"context":{}}))
    response = extension.call(request)

    response.ok.should be_true
    response.result.not_nil!["name"].as_s.should eq("test")
  end

  it "builds host-mediated HTTP effects" do
    effect = CriSDK::Effects.http_request(
      "https://api.example.com/v1",
      secret: "API_TOKEN"
    )

    effect["type"].as_s.should eq("http.request")
    effect["auth"]["secret"].as_s.should eq("API_TOKEN")
  end
end
