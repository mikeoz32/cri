require "json"

module Cri
  class ProviderRegistration
    getter id : String
    getter title : String
    getter transport : String
    getter auth_flows : Array(Auth::Flow)
    getter source : String

    def initialize(
      @id : String,
      @title : String,
      @transport : String,
      @auth_flows : Array(Auth::Flow) = [] of Auth::Flow,
      @source : String = "built-in",
    )
    end

    def auth_flow(id : String) : Auth::Flow
      auth_flows.find { |flow| flow.id == id } || raise "unknown auth flow: #{id}"
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
      all.find { |provider| provider.id == id }
    end

    def register_extension_effect(effect : JSON::Any, extension_name : String)
      payload = effect.as_h
      raise "unsupported extension effect: #{payload["type"]?.try(&.as_s?)}" unless payload["type"]?.try(&.as_s?) == "host.provider.register"

      id = payload["id"]?.try(&.as_s?) || raise "provider registration missing id"
      title = payload["title"]?.try(&.as_s?) || id
      transport = payload["transport"]?.try(&.as_s?) || raise "provider registration missing transport"
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
        Auth::Flow.new(flow["id"].as_s, kind, metadata)
      end
      register(ProviderRegistration.new(
        "extension/#{extension_name}/#{id}",
        title,
        transport,
        flows,
        "extension:#{extension_name}"
      ))
    end
  end
end
