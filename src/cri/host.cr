module Cri
  # Composition root for the trusted Crystal kernel. Features are registered
  # behind narrow interfaces so the CLI/TUI do not know where tools came from.
  class Host
    getter config : Config
    getter events : EventBus
    getter extensions : Extensions::Registry
    getter builtins : ToolRegistry
    getter tools : ToolRouter
    getter invoker : Extensions::Invoker
    getter commands : CommandRegistry
    getter capabilities : API::CapabilityBroker
    getter auth : Auth::Broker
    getter openai_api_credential : Auth::CredentialRef?

    def initialize(
      @config : Config = Config.load,
      @events : EventBus = EventBus.new,
      @capabilities : API::CapabilityBroker = API::CapabilityBroker.deny_all,
      @auth : Auth::Broker = Auth::Broker.new,
    )
      @extensions = Extensions::Registry.new(config.extension_dirs).discover
      @builtins = ToolRegistry.new
      @builtins.register_builtins
      @builtins.register(ReadFileTool.new(config.cwd))
      @builtins.register(ListFilesTool.new(config.cwd))
      register_auth_providers
      @openai_api_credential = auth.import_env("openai-api", "api-key", "OPENAI_API_KEY") || auth.import_env("openai-api", "api-key", "CRI_API_KEY")
      @invoker = Extensions::Invoker.new(grants: config.grants, capabilities: capabilities)
      @tools = ToolRouter.new(@builtins, @extensions, @invoker, config.grants)
      @commands = CommandRegistry.new
      @commands.register_builtin_commands
      register_extension_commands
    end

    def agent(provider : Provider, session : Session = Session.new) : Agent
      Agent.new(provider, tools, events, session)
    end

    def openai_provider : Provider
      api_key = openai_api_credential.try { |ref| auth.secret(ref) }
      Providers::OpenAI.new(api_key: api_key)
    end

    def login_api_token(provider_id : String, flow_id : String, secret : String) : Auth::CredentialRef
      provider = auth.providers.find { |candidate| candidate.id == provider_id }
      raise "unknown auth provider: #{provider_id}" unless provider
      flow = provider.not_nil!.flows.find { |candidate| candidate.id == flow_id }
      raise "unknown auth flow: #{provider_id}/#{flow_id}" unless flow
      raise "auth flow is not an API token flow" unless flow.not_nil!.kind == Auth::FlowKind::ApiToken

      if provider_id == "openai-api" && flow_id == "api-key" && auth.store.persistent?
        Providers::OpenAIAPI::Client.new(api_key: secret).validate_api_key
      end

      ref = auth.import_api_token(provider_id, flow_id, secret)
      @openai_api_credential = ref if provider_id == "openai-api" && flow_id == "api-key"
      ref
    end

    def extension_command(name : String) : Extensions::Manifest?
      extensions.enabled(config.grants).find { |manifest| manifest.commands.any? { |command| command.name == name } }
    end

    private def register_auth_providers
      auth.register(Auth::Provider.new(
        "openai-api",
        "OpenAI API",
        [Auth::Flow.new("api-key", Auth::FlowKind::ApiToken)]
      ))
      auth.register(Auth::Provider.new(
        "openai-codex",
        "ChatGPT / Codex",
        [
          Auth::Flow.new("chatgpt", Auth::FlowKind::OAuthBrowser, {"transport" => "codex-app-server"}),
          Auth::Flow.new("device", Auth::FlowKind::OAuthDevice, {"transport" => "codex-app-server"}),
        ]
      ))

      extensions.enabled(config.grants).each do |manifest|
        manifest.auth_providers.each do |declaration|
          provider_id = "extension/#{manifest.name}/#{declaration.id}"
          flows = declaration.flows.map do |flow|
            kind = case flow.kind
                   when "api_token"     then Auth::FlowKind::ApiToken
                   when "oauth_device"  then Auth::FlowKind::OAuthDevice
                   when "oauth_browser" then Auth::FlowKind::OAuthBrowser
                   else                      raise "invalid auth flow kind: #{flow.kind}"
                   end
            Auth::Flow.new(flow.id, kind, flow.metadata)
          end
          auth.register(Auth::Provider.new(
            provider_id,
            declaration.title,
            flows,
            "extension:#{manifest.name}"
          ))
        end
      end
    end

    private def register_extension_commands
      extensions.enabled(config.grants).each do |manifest|
        manifest.commands.each do |command|
          @commands.register(Command.new(
            command.name,
            command.title || command.name,
            command.description || "Extension command",
            manifest.name
          ))
        end
      end
    end
  end
end
