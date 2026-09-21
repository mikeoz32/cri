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

    def initialize(@config : Config = Config.load, @events : EventBus = EventBus.new, @capabilities : API::CapabilityBroker = API::CapabilityBroker.deny_all)
      @extensions = Extensions::Registry.new(config.extension_dirs).discover
      @builtins = ToolRegistry.new
      @builtins.register_builtins
      @builtins.register(ReadFileTool.new(config.cwd))
      @builtins.register(ListFilesTool.new(config.cwd))
      @invoker = Extensions::Invoker.new(grants: config.grants, capabilities: capabilities)
      @tools = ToolRouter.new(@builtins, @extensions, @invoker, config.grants)
      @commands = CommandRegistry.new
      @commands.register_builtin_commands
      register_extension_commands
    end

    def agent(provider : Provider, session : Session = Session.new) : Agent
      Agent.new(provider, tools, events, session)
    end

    def extension_command(name : String) : Extensions::Manifest?
      extensions.enabled(config.grants).find { |manifest| manifest.commands.any? { |command| command.name == name } }
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
