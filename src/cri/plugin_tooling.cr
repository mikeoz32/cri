module Cri
  class PluginTooling
    getter root : String

    def initialize(@root : String = Dir.current)
    end

    def init(language : String, name : String, destination : String?) : Bool
      case language
      when "zig"
        init_zig(name, destination || name)
      else
        STDERR.puts "unsupported SDK: #{language}"
        STDERR.puts "available SDKs: zig"
        false
      end
    end

    def check(project : String) : Bool
      manifest_path = File.join(project, "extension.toml")
      unless File.file?(manifest_path)
        STDERR.puts "missing extension.toml: #{manifest_path}"
        return false
      end

      manifest = Extensions::Manifest.load(manifest_path, false)
      unless manifest.valid?
        manifest.errors.each { |error| STDERR.puts "invalid: #{error}" }
        return false
      end

      case manifest.sdk
      when "zig"
        unless executable_available?("zig")
          STDERR.puts "zig executable not found"
          return false
        end
      when nil
        STDERR.puts "warning: manifest has no sdk metadata"
      else
        STDERR.puts "unsupported SDK: #{manifest.sdk}"
        return false
      end

      if wasm_path = manifest.wasm_path
        unless File.file?(wasm_path)
          puts "warning: WASM artifact not built: #{wasm_path}"
        else
          conformance = Wasm::ConformanceChecker.new.check(wasm_path)
          unless conformance.valid?
            conformance.errors.each { |error| STDERR.puts "WASM invalid: #{error}" }
            return false
          end
          puts "WASM exports: #{conformance.exports.join(", ")}"
          puts "WASM imports: none"
        end
      end
      puts "valid #{manifest.name} (sdk=#{manifest.sdk || "unknown"})"
      true
    end

    def test(project : String, input : JSON::Any = JSON.parse("{}")) : Bool
      return false unless check(project)
      manifest = Extensions::Manifest.load(File.join(project, "extension.toml"), false)
      tool = manifest.tools.first?
      unless tool
        STDERR.puts "plugin test requires at least one declared tool"
        return false
      end
      unless manifest.wasm_path && File.file?(manifest.wasm_path.not_nil!)
        STDERR.puts "WASM artifact not found; run cri plugin build first"
        return false
      end

      {% if flag?(:wasm3) || flag?(:Wasm3) %}
        request = Wasm::RequestEnvelope.new("tool", tool.name, input)
        handler = Effects::Handler.new(config_grants(manifest.name), manifest.permissions)
        response = Wasm::Wasm3Runtime.new.run(manifest, request, handler)
        puts response.to_json
        response.ok
      {% else %}
        STDERR.puts "plugin test requires cri built with -Dwasm3 (or -DWasm3)"
        false
      {% end %}
    end

    def build(project : String) : Bool
      return false unless check(project)
      manifest = Extensions::Manifest.load(File.join(project, "extension.toml"), false)

      case manifest.sdk
      when "zig"
        script = File.join(root, "sdk", "zig", "build.sh")
        unless File::Info.executable?(script)
          STDERR.puts "Zig SDK build script not found: #{script}"
          return false
        end
        Process.run(script, args: [project], output: Process::Redirect::Inherit, error: Process::Redirect::Inherit).success?
      else
        STDERR.puts "no build adapter for SDK: #{manifest.sdk || "unknown"}"
        false
      end
    end

    private def config_grants(name : String) : Permissions::GrantSet
      Config.load(root).grants.for_extension(name)
    end

    private def init_zig(name : String, destination : String) : Bool
      destination = File.expand_path(destination, root)
      if Dir.exists?(destination) && !Dir.empty?(destination)
        STDERR.puts "destination is not empty: #{destination}"
        return false
      end

      template = File.join(root, "sdk", "zig", "template")
      Dir.mkdir_p(File.join(destination, "src"))
      File.write(
        File.join(destination, "extension.toml"),
        File.read(File.join(template, "extension.toml")).gsub("{{NAME}}", name)
      )
      File.write(
        File.join(destination, "src", "main.zig"),
        File.read(File.join(template, "src", "main.zig"))
      )
      puts "created Zig extension: #{destination}"
      puts "next: cri plugin check #{destination}"
      puts "then: cri plugin build #{destination}"
      true
    rescue ex
      STDERR.puts "could not initialize extension: #{ex.message || ex.class.name}"
      false
    end

    private def executable_available?(name : String) : Bool
      Process.run("sh", args: ["-c", "command -v #{name} >/dev/null 2>&1"], output: Process::Redirect::Close, error: Process::Redirect::Close).success?
    end
  end
end
