module Cri
  class Command
    getter name : String
    getter title : String
    getter description : String
    getter source : String

    def initialize(@name : String, @title : String, @description : String = "", @source : String = "builtin")
    end
  end

  class CommandRegistry
    getter commands = {} of String => Command

    def register(command : Command)
      @commands[command.name] = command
    end

    def register_builtin_commands
      register(Command.new("help", "Show help", source: "builtin"))
      register(Command.new("tools", "List available tools", source: "builtin"))
      register(Command.new("extensions", "List loaded extensions", source: "builtin"))
      register(Command.new("auth", "Show authentication providers", source: "builtin"))
      register(Command.new("session", "Show current session", source: "builtin"))
      register(Command.new("clear", "Clear current session", source: "builtin"))
      register(Command.new("exit", "Exit cri", source: "builtin"))
    end

    def names : Array(String)
      commands.keys.sort
    end

    def find(name : String) : Command?
      commands[name]?
    end
  end
end
