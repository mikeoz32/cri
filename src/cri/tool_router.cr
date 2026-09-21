module Cri
  class ToolRouter < ToolExecutor
    getter builtins : ToolRegistry
    getter extensions : Extensions::Registry
    getter invoker : Extensions::Invoker
    getter grants : Permissions::GrantPolicy

    def initialize(@builtins : ToolRegistry, @extensions : Extensions::Registry, @invoker : Extensions::Invoker, @grants : Permissions::GrantPolicy = Permissions::GrantPolicy.default)
    end

    def names : Array(String)
      names = builtins.names
      extensions.enabled(grants).each do |manifest|
        manifest.tools.each { |tool| names << tool.name }
      end
      names.uniq.sort
    end

    def specs : Array(ToolSpec)
      specs = builtins.specs
      extensions.enabled(grants).each do |manifest|
        manifest.tools.each do |tool|
          specs << ToolSpec.new(tool.name, tool.description || "Extension tool #{tool.name}")
        end
      end
      specs.uniq { |spec| spec.name }
    end

    def call(name : String, input : JSON::Any) : ToolResult
      request = API::CapabilityRequest.new(
        "tool-#{Random::Secure.hex(12)}",
        "agent",
        "tool.call",
        name,
        "Execute tool #{name}"
      )
      return ToolResult.new(false, nil, "capability approval denied") unless invoker.capabilities.authorize(request)

      return builtins.call(name, input) if builtins.names.includes?(name)

      manifest = extensions.enabled(grants).find { |candidate| candidate.tools.any? { |tool| tool.name == name } }
      return ToolResult.new(false, nil, "unknown tool: #{name}") unless manifest

      response = invoker.invoke(manifest, "tool", name, input)
      ToolResult.new(response.ok, response.result, response.error)
    end
  end
end
