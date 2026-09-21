module CriSDK
  module Effects
    def self.http_request(
      url : String,
      method : String = "GET",
      headers : Hash(String, String) = {} of String => String,
      body : JSON::Any? = nil,
      secret : String? = nil,
      auth : String = "bearer"
    ) : JSON::Any
      payload = JSON.build do |json|
        json.object do
          json.field "type", "http.request"
          json.field "url", url
          json.field "method", method
          unless headers.empty?
            json.field "headers" do
              json.object do
                headers.each { |key, value| json.field key, value }
              end
            end
          end
          json.field "body", body if body
          if secret
            json.field "auth" do
              json.object do
                json.field "secret", secret
                json.field "as", auth
              end
            end
          end
        end
      end
      JSON.parse(payload)
    end

    def self.read_file(path : String) : JSON::Any
      JSON.parse({"type" => "file.read", "path" => path}.to_json)
    end

    def self.propose_edit(path : String, content : String) : JSON::Any
      JSON.parse({
        "type" => "file.propose_edit",
        "path" => path,
        "content" => content,
      }.to_json)
    end

    def self.notify(message : String, level : String = "info") : JSON::Any
      JSON.parse({
        "type" => "ui.notification",
        "message" => message,
        "level" => level,
      }.to_json)
    end
  end
end
