module Cri
  module Tui
    class Controller
      getter host : Host
      getter agent : Agent

      def initialize(@host : Host, provider : Provider? = nil)
        @agent = host.agent(provider || host.default_provider)
      end

      def submit(input : String) : Tuple(Bool, String)
        submit(input) { |_chunk| }
      end

      def submit(input : String, &on_text : String -> Nil) : Tuple(Bool, String)
        if input.starts_with?("/")
          dispatch_command(input[1..-1])
        else
          {true, agent.run_turn(input) { |chunk| on_text.call(chunk) }}
        end
      end

      private def dispatch_command(raw : String) : Tuple(Bool, String)
        parts = raw.split(" ", 2)
        name = parts[0]
        args = parts.size > 1 ? parts[1] : ""

        case name
        when "q", "exit", "quit"
          {false, "bye"}
        when "help"
          {true, help_text}
        when "tools"
          {true, host.tools.names.join("\n")}
        when "extensions"
          {true, extensions_text}
        when "auth"
          {true, auth_text(args)}
        when "provider"
          provider_command(args)
        when "session"
          {true, "session: #{agent.session.id}\nmessages: #{agent.session.messages.size}"}
        when "clear"
          agent.session.clear
          {true, "session cleared"}
        else
          {true, execute_extension_command(name, args)}
        end
      end

      private def help_text : String
        lines = ["Commands:"]
        host.commands.names.each do |name|
          command = host.commands.find(name).not_nil!
          lines << "/#{name} — #{command.title}"
        end
        lines.join("\n")
      end

      private def extensions_text : String
        return "no valid extensions" if host.extensions.valid.empty?
        host.extensions.valid.map { |manifest| "#{manifest.name} #{manifest.version}" }.join("\n")
      end

      private def provider_command(args : String) : Tuple(Bool, String)
        if args.empty?
          lines = ["Providers:"]
          host.providers.all.each do |provider|
            marker = agent.provider.registration.try(&.id) == provider.id ? "*" : " "
            lines << "#{marker} #{provider.id} — #{provider.title} (#{provider.api_type})"
          end
          return {true, lines.join("\n")}
        end

        parts = args.split
        provider_id = parts[0]
        flow_id = parts[1]?
        begin
          @agent = host.agent(host.provider(provider_id, flow_id), agent.session)
          {true, "selected provider #{provider_id}#{flow_id ? "/#{flow_id}" : ""}"}
        rescue ex
          {true, "provider selection failed: #{ex.message || ex.class.name}"}
        end
      end

      private def auth_text(args : String)
        parts = args.split
        if parts[0]? == "logout"
          provider_id = parts[1]?
          return "usage: /auth logout PROVIDER [FLOW]" unless provider_id
          provider = host.providers.find(provider_id)
          return "unknown auth provider: #{provider_id}" unless provider
          flow_id = parts[2]? || provider.not_nil!.auth_flows.first?.try(&.id)
          return "provider has no auth flows" unless flow_id
          begin
            host.logout_auth(provider_id, flow_id)
            return "logged out #{provider_id}/#{flow_id}"
          rescue ex
            return "logout failed: #{ex.message || ex.class.name}"
          end
        end

        return "usage: /auth [status|providers|login|logout]" unless args.empty? || args == "status" || args == "providers" || parts[0]? == "login"

        lines = ["Authentication providers:"]
        host.providers.all.each do |provider|
          lines << "#{provider.title} (#{provider.source})"
          provider.auth_flows.each do |flow|
            configured = host.auth.existing(provider.id, flow.id) ? "configured" : "not configured"
            lines << "  #{flow.id}: #{configured}"
          end
        end
        lines.join("\n")
      end

      private def execute_extension_command(name : String, args : String) : String
        command = host.commands.find(name)
        return "unknown command: /#{name}" unless command && command.source != "builtin"

        manifest = host.extension_command(name)
        return "extension command unavailable: /#{name}" unless manifest

        input = parse_command_input(args)
        response = host.invoker.invoke(manifest.not_nil!, "command", name, input)
        response.to_json
      end

      private def parse_command_input(args : String) : JSON::Any
        return JSON.parse("{}") if args.empty?
        JSON.parse(args)
      rescue JSON::ParseException
        JSON.parse({"args" => args}.to_json)
      end
    end
  end
end
