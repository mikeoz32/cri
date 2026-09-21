module Cri
  class CLI
    def self.run(argv : Array(String))
      new(Config.load).run(argv)
    end

    getter config : Config
    getter host : Host

    def initialize(@config : Config)
      @host = Host.new(config)
    end

    def run(argv : Array(String))
      command = argv.shift?
      case command
      when nil, "help", "--help", "-h"
        print_help
      when "version"
        puts "cri #{VERSION}"
      when "doctor"
        doctor
      when "extensions"
        extensions(argv)
      when "auth"
        auth(argv)
      when "plugin"
        plugin(argv)
      when "tool"
        tool(argv)
      when "chat"
        chat
      when "tui"
        Tui::Shell.new(host).run
      else
        STDERR.puts "unknown command: #{command}"
        print_help
        exit 1
      end
    end

    private def print_help
      puts <<-TEXT
      cri #{VERSION}

      Usage:
        cri version
        cri doctor
        cri extensions list
        cri extensions show NAME
        cri extensions invoke NAME KIND CONTRIBUTION JSON
        cri auth status
        cri auth login PROVIDER [FLOW]
        cri auth logout PROVIDER [FLOW]
        cri plugin init --lang zig NAME [DIR]
        cri plugin check DIR
        cri plugin build DIR
        cri plugin test DIR [JSON]
        cri plugin pack DIR [OUTPUT]
        cri plugin install PACKAGE
        cri plugin remove NAME
        cri tool list
        cri tool call NAME JSON
        cri chat
        cri tui
      TEXT
    end

    private def auth(argv : Array(String))
      sub = argv.shift? || "status"
      case sub
      when "status", "providers"
        host.providers.all.each do |provider|
          puts "#{provider.title} (#{provider.source})"
          provider.auth_flows.each do |flow|
            state = host.auth.existing(provider.id, flow.id) ? "configured" : "not configured"
            puts "  #{flow.id}: #{state}"
          end
        end
      when "login"
        provider_id = argv.shift? || abort("missing auth provider")
        provider = host.providers.find(provider_id)
        abort("unknown auth provider: #{provider_id}") unless provider
        flow_id = argv.shift? || provider.not_nil!.auth_flows.first?.try(&.id) || abort("provider has no flows")
        flow = provider.not_nil!.auth_flows.find { |candidate| candidate.id == flow_id }
        abort("unknown auth flow: #{provider_id}/#{flow_id}") unless flow
        case flow.not_nil!.kind
        when Auth::FlowKind::ApiToken
          token = read_secret("#{provider.not_nil!.title} API token: ")
          abort("empty token") if token.empty?
          begin
            ref = host.login_api_token(provider_id, flow_id, token)
            puts "saved #{provider_id}/#{flow_id} as #{ref.id}"
          rescue ex
            abort("authentication failed: #{ex.message || ex.class.name}")
          end
        else
          abort("#{provider_id}/#{flow_id} login transport is not implemented yet")
        end
      when "logout"
        provider_id = argv.shift? || abort("missing auth provider")
        provider = host.providers.find(provider_id)
        abort("unknown auth provider: #{provider_id}") unless provider
        flow_id = argv.shift? || provider.not_nil!.auth_flows.first?.try(&.id) || abort("provider has no flows")
        host.auth.logout(provider_id, flow_id)
        puts "logged out #{provider_id}/#{flow_id}"
      else
        STDERR.puts "usage: cri auth status | login PROVIDER [FLOW] | logout PROVIDER [FLOW]"
        exit 1
      end
    end

    private def read_secret(prompt : String) : String
      STDERR.print(prompt)
      output = IO::Memory.new
      status = Process.run("stty", args: ["-g"], input: Process::Redirect::Inherit, output: output, error: Process::Redirect::Close)
      if status.success?
        state = output.to_s.strip
        Process.run("stty", args: ["-echo"], input: Process::Redirect::Inherit, output: Process::Redirect::Close)
        begin
          return STDIN.gets.to_s.chomp
        ensure
          Process.run("stty", args: [state], input: Process::Redirect::Inherit, output: Process::Redirect::Close)
          STDERR.puts
        end
      end
      STDIN.gets.to_s.chomp
    end

    private def doctor
      puts "cri #{VERSION}"
      puts "abi: #{ABI_VERSION}"
      puts "cwd: #{config.cwd}"
      puts "extension dirs:"
      config.extension_dirs.each { |dir| puts "  - #{dir} #{Dir.exists?(dir) ? "(exists)" : "(missing)"}" }
      config.grants.errors.each { |error| puts "grant config error: #{error}" }
    end

    private def extensions(argv : Array(String))
      sub = argv.shift? || "list"
      case sub
      when "list"
        registry = host.extensions
        if registry.manifests.empty?
          puts "no extensions found"
          return
        end
        registry.manifests.each do |m|
          status = if !m.valid?
                     "invalid: #{m.errors.join("; ")}"
                   elsif !config.grants.enabled?(m.name)
                     "disabled"
                   else
                     "valid"
                   end
          puts "#{m.name.empty? ? "<unnamed>" : m.name} #{m.version} [#{status}]"
          m.all_contributions.each { |c| puts "  - #{c.kind}: #{c.name}" }
        end
      when "show"
        name = argv.shift? || abort("missing extension name")
        manifest = host.extensions.find(name)
        abort("extension not found: #{name}") unless manifest
        puts "name: #{manifest.name}"
        puts "version: #{manifest.version}"
        puts "abi: #{manifest.abi}"
        puts "enabled: #{config.grants.enabled?(manifest.name)}"
        puts "wasm: #{manifest.wasm_path || "<none>"}"
        puts "permissions:"
        puts "  network: #{manifest.permissions.network.join(", ")}"
        puts "  secrets: #{manifest.permissions.secrets.join(", ")}"
        puts "  filesystem_read: #{manifest.permissions.filesystem_read.join(", ")}"
        puts "  filesystem_write: #{manifest.permissions.filesystem_write.join(", ")}"
        puts "  shell: #{manifest.permissions.shell}"
        puts "  model: #{manifest.permissions.model}"
      when "invoke"
        name = argv.shift? || abort("missing extension name")
        kind = argv.shift? || abort("missing contribution kind")
        contribution = argv.shift? || abort("missing contribution name")
        input = JSON.parse(argv.shift? || "{}")
        registry = host.extensions
        manifest = registry.find(name)
        abort("extension not found: #{name}") unless manifest
        abort("invalid extension: #{manifest.errors.join("; ")}") unless manifest.valid?
        result = host.invoker.invoke(manifest, kind, contribution, input)
        puts result.to_json
      else
        STDERR.puts "unknown extensions subcommand: #{sub}"
        exit 1
      end
    end

    private def plugin(argv : Array(String))
      sub = argv.shift? || "help"
      tooling = PluginTooling.new(config.cwd)

      case sub
      when "init"
        language = ""
        while argument = argv.first?
          break unless argument.starts_with?("--")
          argv.shift
          option = argument.split("=", 2)
          key = option[0]
          value = option[1]?
          if key == "--lang"
            language = value || argv.shift? || ""
          end
        end
        name = argv.shift? || abort("missing plugin name")
        destination = argv.shift?
        abort("missing --lang") if language.empty?
        exit 1 unless tooling.init(language, name, destination)
      when "check"
        project = argv.shift? || "."
        exit 1 unless tooling.check(project)
      when "build"
        project = argv.shift? || "."
        exit 1 unless tooling.build(project)
      when "test"
        project = argv.shift? || "."
        input = JSON.parse(argv.shift? || "{}")
        exit 1 unless tooling.test(project, input)
      when "pack"
        project = argv.shift? || "."
        output = argv.shift?
        exit 1 unless PluginPackage.new(config.cwd).pack(project, output)
      when "install"
        package_path = argv.shift? || abort("missing package path")
        exit 1 unless PluginPackage.new(config.cwd).install(package_path)
      when "remove"
        name = argv.shift? || abort("missing plugin name")
        exit 1 unless PluginPackage.new(config.cwd).remove(name)
      else
        STDERR.puts "usage: cri plugin init --lang zig NAME [DIR] | check DIR | build DIR"
        exit 1
      end
    end

    private def chat
      Tui::Shell.new(host).run
    end

    private def tool(argv : Array(String))
      sub = argv.shift?
      case sub
      when "list"
        host.tools.names.each { |name| puts name }
      when "call"
        name = argv.shift? || abort("missing tool name")
        input_raw = argv.shift? || "{}"
        result = host.tools.call(name, JSON.parse(input_raw))
        puts result.to_json
      else
        STDERR.puts "usage: cri tool list | cri tool call NAME JSON"
        exit 1
      end
    end
  end
end
