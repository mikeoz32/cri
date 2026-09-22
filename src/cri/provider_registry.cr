require "json"

module Cri
  class ModelRef
    getter id : String
    getter provider_id : String
    getter model : String
    getter title : String
    getter auth_flow_id : String?
    getter api_type : String?
    getter endpoint : String?
    getter transport_type : String?

    def initialize(
      @id : String,
      @provider_id : String,
      @model : String,
      @title : String = @model,
      @auth_flow_id : String? = nil,
      @api_type : String? = nil,
      @endpoint : String? = nil,
      @transport_type : String? = nil,
    )
    end
  end

  class ProviderRegistration
    getter id : String
    getter title : String
    getter api_type : String
    getter endpoint : String
    getter model : String
    getter transport_type : String
    getter auth_flows : Array(Auth::Flow)
    getter source : String
    getter models : Array(ModelRef)

    def initialize(
      @id : String,
      @title : String,
      @api_type : String,
      @endpoint : String,
      @model : String,
      @transport_type : String = "http+sse",
      @auth_flows : Array(Auth::Flow) = [] of Auth::Flow,
      @source : String = "built-in",
      @models : Array(ModelRef) = [] of ModelRef,
    )
    end

    def model_refs : Array(ModelRef)
      return models unless models.empty?
      [ModelRef.new("#{id}/#{model}", id, model, model, auth_flows.first?.try(&.id), api_type, endpoint, transport_type)]
    end

    def auth_flow(id : String) : Auth::Flow
      auth_flows.find { |flow| flow.id == id } || raise "unknown auth flow: #{id}"
    end

    def for_model(model_ref : ModelRef) : self
      self.class.new(
        id, title,
        model_ref.api_type || api_type,
        model_ref.endpoint || endpoint,
        model_ref.model,
        model_ref.transport_type || transport_type,
        auth_flows, source, models
      )
    end

    def for_flow(flow : Auth::Flow) : self
      self.class.new(
        id,
        title,
        flow.metadata["api_type"]? || api_type,
        flow.metadata["endpoint"]? || endpoint,
        flow.metadata["model"]? || model,
        flow.metadata["transport"]? || transport_type,
        [flow],
        source
      )
    end

    def to_auth_provider : Auth::Provider
      Auth::Provider.new(id, title, auth_flows, source)
    end
  end

  class ProviderRegistry
    getter all : Array(ProviderRegistration)

    def initialize(@auth : Auth::Broker)
      @all = [] of ProviderRegistration
    end

    def register(provider : ProviderRegistration) : ProviderRegistration
      raise "duplicate provider: #{provider.id}" if @all.any? { |item| item.id == provider.id }
      @all << provider
      @auth.register(provider.to_auth_provider)
      provider
    end

    def find(id : String) : ProviderRegistration?
      exact = all.find { |provider| provider.id == id }
      return exact if exact
      matches = all.select { |provider| provider.id == "extension/#{id}/#{id}" || provider.id.ends_with?("/#{id}") }
      matches.size == 1 ? matches.first : nil
    end

    def models : Array(ModelRef)
      all.flat_map(&.model_refs)
    end

    def find_model(id : String) : ModelRef?
      models.find { |model| model.id == id }
    end

    def register_extension_effect(effect : JSON::Any, extension_name : String)
      payload = effect.as_h
      raise "unsupported extension effect: #{payload["type"]?.try(&.as_s?)}" unless payload["type"]?.try(&.as_s?) == "host.provider.register"

      id = payload["id"]?.try(&.as_s?) || raise "provider registration missing id"
      title = payload["title"]?.try(&.as_s?) || id
      api_type = payload["api_type"]?.try(&.as_s?) || raise "provider registration missing api_type"
      endpoint = payload["endpoint"]?.try(&.as_s?) || raise "provider registration missing endpoint"
      default_model = payload["model"]?.try(&.as_s?) || ""
      transport_type = payload["transport"]?.try(&.as_s?) || "http+sse"
      flows = payload["auth_flows"]?.try(&.as_a).not_nil!.map do |flow_json|
        flow = flow_json.as_h
        kind = case flow["kind"]?.try(&.as_s?)
               when "api_token"     then Auth::FlowKind::ApiToken
               when "oauth_device"  then Auth::FlowKind::OAuthDevice
               when "oauth_browser" then Auth::FlowKind::OAuthBrowser
               else                      raise "unsupported auth flow kind"
               end
        metadata = {} of String => String
        if metadata_json = flow["metadata"]?.try(&.as_h)
          metadata_json.each { |key, value| metadata[key] = value.as_s }
        end
        oauth = parse_oauth_config(flow["oauth"]?)
        Auth::Flow.new(flow["id"].as_s, kind, metadata, oauth)
      end
      models = payload["models"]?.try(&.as_a).try do |items|
        items.map do |item|
          model_json = item.as_h
          ModelRef.new(
            "extension/#{extension_name}/#{id}/#{model_json["id"].as_s}",
            "extension/#{extension_name}/#{id}",
            model_json["model"]?.try(&.as_s) || model_json["id"].as_s,
            model_json["title"]?.try(&.as_s) || model_json["id"].as_s,
            model_json["auth_flow"]?.try(&.as_s?),
            model_json["api_type"]?.try(&.as_s?),
            model_json["endpoint"]?.try(&.as_s?),
            model_json["transport"]?.try(&.as_s?)
          )
        end
      end || [] of ModelRef
      register(ProviderRegistration.new(
        "extension/#{extension_name}/#{id}", title, api_type, endpoint, default_model,
        transport_type, flows, "extension:#{extension_name}", models
      ))
    end

    private def parse_oauth_config(value : JSON::Any?) : Auth::OAuthConfig?
      return nil unless json = value
      config = json.as_h
      token_endpoint = config["token_endpoint"]?.try(&.as_s) || raise "OAuth config missing token_endpoint"
      client_id = config["client_id"]?.try(&.as_s) || raise "OAuth config missing client_id"
      scopes = config["scopes"]?.try(&.as_a).try(&.map(&.as_s)) || [] of String
      extras = {} of String => String
      config["extra_parameters"]?.try(&.as_h).try(&.each { |key, item| extras[key] = item.as_s })
      Auth::OAuthConfig.new(
        token_endpoint,
        client_id,
        config["authorization_endpoint"]?.try(&.as_s?),
        config["device_authorization_endpoint"]?.try(&.as_s?),
        scopes,
        config["redirect_uri"]?.try(&.as_s?),
        config["audience"]?.try(&.as_s?),
        extras
      )
    end
  end
end
