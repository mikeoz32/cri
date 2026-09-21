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
  end
end
