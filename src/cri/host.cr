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
    getter providers : ProviderRegistry
    getter transports : Transports::Registry
    getter api_clients : APIClientRegistry

    def initialize(
      @config : Config = Config.load,
      @events : EventBus = EventBus.new,
      @capabilities : API::CapabilityBroker = API::CapabilityBroker.deny_all,
      @auth : Auth::Broker = Auth::Broker.new,
    )
      @extensions = Extensions::Registry.new(config.extension_dirs).discover
      @transports = Transports::Registry.new
      @api_clients = APIClientRegistry.new
      register_api_clients
      @providers = ProviderRegistry.new(auth)
      @builtins = ToolRegistry.new
      @builtins.register_builtins
      @builtins.register(ReadFileTool.new(config.cwd))
      @builtins.register(ListFilesTool.new(config.cwd))
      @invoker = Extensions::Invoker.new(grants: config.grants, capabilities: capabilities)
      register_extension_provider_hooks
      @tools = ToolRouter.new(@builtins, @extensions, @invoker, config.grants)
      @commands = CommandRegistry.new
      @commands.register_builtin_commands
      register_extension_commands
    end

    def agent(provider : Provider, session : Session = Session.new) : Agent
      Agent.new(provider, tools, events, session)
    end

    def default_provider : Provider
      provider_id = config.provider_id
      if provider_id
        return provider(provider_id)
      end
      registration = providers.all.first? || raise "no provider registered; load a provider extension first"
      provider(registration.id, config.auth_flow_id)
    rescue ex : Exception
      raise "unable to select provider#{provider_id ? " '#{provider_id}'" : ""}: #{ex.message}"
    end

    def provider(provider_id : String, flow_id : String? = nil) : Provider
      registration = providers.find(provider_id) || raise "unknown provider: #{provider_id}"
      selected_flow_id = flow_id || config.auth_flow_id
      flow = if selected_flow_id
               registration.auth_flow(selected_flow_id)
             else
               registration.auth_flows.first? || raise "provider has no auth flows: #{provider_id}"
             end
      ref = auth.existing(provider_id, flow.id)
      unless ref
        if env_name = flow.metadata["env"]?
          ref = auth.import_env(provider_id, flow.id, env_name)
        end
      end
      effective = registration.for_flow(flow)
      secret = ref.try { |credential| auth.secret(credential) }
      Provider.new(effective, api_clients.build(effective, secret))
    end

    def login_api_token(provider_id : String, flow_id : String, secret : String) : Auth::CredentialRef
      provider = providers.find(provider_id)
      raise "unknown auth provider: #{provider_id}" unless provider
      flow = provider.not_nil!.auth_flows.find { |candidate| candidate.id == flow_id }
      raise "unknown auth flow: #{provider_id}/#{flow_id}" unless flow
      raise "auth flow is not an API token flow" unless flow.not_nil!.kind == Auth::FlowKind::ApiToken

      effective = provider.not_nil!.for_flow(flow.not_nil!)
      if flow.not_nil!.metadata["validate"]? == "api_client" && auth.store.persistent?
        api_clients.validate(effective, secret)
      end

      auth.import_api_token(provider_id, flow_id, secret)
    end

    def login_device(provider_id : String, flow_id : String, &on_status : String ->) : Auth::CredentialRef
      provider = providers.find(provider_id)
      raise "unknown auth provider: #{provider_id}" unless provider
      flow = provider.not_nil!.auth_flows.find { |candidate| candidate.id == flow_id }
      raise "unknown auth flow: #{provider_id}/#{flow_id}" unless flow
      raise "auth flow is not a device flow" unless flow.not_nil!.kind == Auth::FlowKind::OAuthDevice
      config = flow.not_nil!.oauth || raise "OAuth device flow has no configuration"
      tokens = Auth::OAuthClient.new.device_login(config) { |status| on_status.call(status) }
      auth.import_opaque(provider_id, flow_id, tokens.to_json)
    end

    def login_browser(provider_id : String, flow_id : String, &on_status : String ->) : Auth::CredentialRef
      provider = providers.find(provider_id)
      raise "unknown auth provider: #{provider_id}" unless provider
      flow = provider.not_nil!.auth_flows.find { |candidate| candidate.id == flow_id }
      raise "unknown auth flow: #{provider_id}/#{flow_id}" unless flow
      raise "auth flow is not a browser OAuth flow" unless flow.not_nil!.kind == Auth::FlowKind::OAuthBrowser
      config = flow.not_nil!.oauth || raise "OAuth browser flow has no configuration"
      tokens = Auth::OAuthClient.new.browser_login(config) { |status| on_status.call(status) }
      auth.import_opaque(provider_id, flow_id, tokens.to_json)
    end

    def extension_command(name : String) : Extensions::Manifest?
      extensions.enabled(config.grants).find { |manifest| manifest.commands.any? { |command| command.name == name } }
    end

    private def register_api_clients
      api_clients.register("openai") do |registration, secret|
        transport = transports.build(registration.transport_type)
        APIClients::OpenAICompatible.new(registration.endpoint, registration.model, secret, transport: transport)
      end
      api_clients.register("openai-codex-responses") do |registration, secret|
        transport = transports.build(registration.transport_type)
        APIClients::OpenAICodexResponses.new(registration.endpoint, registration.model, secret, transport)
      end
    end

    private def register_extension_provider_hooks
      return unless invoker.available?
      input = JSON.parse({"event" => "host.init"}.to_json)
      extensions.enabled(config.grants).each do |manifest|
        manifest.hooks.select { |hook| hook.name == "init" }.each do |hook|
          response = invoker.invoke(
            manifest,
            "hook",
            hook.name,
            input,
            provider_sink: ->(effect : JSON::Any) {
              providers.register_extension_effect(effect, manifest.name)
              nil
            }
          )
          raise "extension #{manifest.name} init failed: #{response.error}" unless response.ok
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
