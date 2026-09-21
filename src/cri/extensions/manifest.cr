require "set"

module Cri
  module Extensions
    class Contribution
      include JSON::Serializable

      property kind : String
      property name : String
      property title : String?
      property description : String?
      property event : String?
      property entrypoint : String

      def initialize(@kind : String, @name : String, @title : String? = nil, @description : String? = nil, @event : String? = nil, @entrypoint : String = "cri_call")
      end
    end

    class AuthFlowDeclaration
      property id : String = ""
      property kind : String = ""
      property metadata = {} of String => String
    end

    class AuthProviderDeclaration
      property id : String = ""
      property title : String = ""
      property flows = [] of AuthFlowDeclaration
    end

    class Manifest
      getter root_dir : String
      property name : String = ""
      property version : String = ""
      property abi : String = ""
      property sdk : String?
      property sdk_version : String?
      property wasm : String?
      property permissions : Permissions::Request = Permissions::Request.new
      property tools = [] of Contribution
      property commands = [] of Contribution
      property hooks = [] of Contribution
      property context_providers = [] of Contribution
      property ui_status_items = [] of Contribution
      property ui_panels = [] of Contribution
      property ui_actions = [] of Contribution
      property auth_providers = [] of AuthProviderDeclaration
      property errors = [] of String

      def initialize(@root_dir : String)
      end

      def self.load(path : String, require_wasm : Bool = true) : self
        manifest = new(File.dirname(path))
        manifest.parse(File.read(path))
        manifest.validate(require_wasm)
        manifest
      rescue ex
        m = new(File.dirname(path))
        m.errors << "failed to read manifest: #{ex.message}"
        m
      end

      def valid? : Bool
        errors.empty?
      end

      def wasm_path : String?
        wasm.try { |w| File.expand_path(w, root_dir) }
      end

      protected def parse(source : String)
        section = "root"
        current : Contribution? = nil
        current_auth_provider : AuthProviderDeclaration? = nil
        current_auth_flow : AuthFlowDeclaration? = nil

        source.each_line do |raw|
          line = raw.strip
          next if line.empty? || line.starts_with?("#")

          case line
          when "[permissions]"
            section = "permissions"
            current = nil
            current_auth_provider = nil
            current_auth_flow = nil
            next
          when "[[auth.providers]]"
            section = "auth.providers"
            current = nil
            current_auth_flow = nil
            current_auth_provider = AuthProviderDeclaration.new
            auth_providers << current_auth_provider.not_nil!
            next
          when "[[auth.providers.flows]]"
            section = "auth.providers.flows"
            current = nil
            provider = current_auth_provider
            unless provider
              errors << "auth flow must follow an auth provider"
              next
            end
            current_auth_flow = AuthFlowDeclaration.new
            provider.flows << current_auth_flow.not_nil!
            next
          when "[[tools]]"
            section = "tools"
            current_auth_provider = nil
            current_auth_flow = nil
            current = Contribution.new("tool", "")
            tools << current.not_nil!
            next
          when "[[commands]]"
            section = "commands"
            current_auth_provider = nil
            current_auth_flow = nil
            current = Contribution.new("command", "")
            commands << current.not_nil!
            next
          when "[[hooks]]"
            section = "hooks"
            current_auth_provider = nil
            current_auth_flow = nil
            current = Contribution.new("hook", "")
            hooks << current.not_nil!
            next
          when "[[context_providers]]"
            section = "context"
            current_auth_provider = nil
            current_auth_flow = nil
            current = Contribution.new("context", "")
            context_providers << current.not_nil!
            next
          when "[[ui.status_items]]"
            section = "ui.status_items"
            current_auth_provider = nil
            current_auth_flow = nil
            current = Contribution.new("ui.status_item", "")
            ui_status_items << current.not_nil!
            next
          when "[[ui.panels]]"
            section = "ui.panels"
            current_auth_provider = nil
            current_auth_flow = nil
            current = Contribution.new("ui.panel", "")
            ui_panels << current.not_nil!
            next
          when "[[ui.actions]]"
            section = "ui.actions"
            current_auth_provider = nil
            current_auth_flow = nil
            current = Contribution.new("ui.action", "")
            ui_actions << current.not_nil!
            next
          end

          if line.starts_with?("[")
            errors << "unsupported manifest section: #{line}"
            next
          end

          key, value = parse_key_value(line)
          unless key
            errors << "invalid manifest line: #{line}"
            next
          end

          case section
          when "root"
            assign_root(key, value)
          when "permissions"
            assign_permission(key, value)
          when "auth.providers"
            assign_auth_provider(current_auth_provider, key, value)
          when "auth.providers.flows"
            assign_auth_flow(current_auth_flow, key, value)
          else
            assign_contribution(current, key, value)
          end
        end
      end

      private def parse_key_value(line : String) : Tuple(String?, String)
        parts = line.split("=", 2)
        return {nil, ""} unless parts.size == 2
        {parts[0].strip, parts[1].strip}
      end

      private def assign_root(key : String, value : String)
        case key
        when "name"        then @name = scalar(value)
        when "version"     then @version = scalar(value)
        when "abi"         then @abi = scalar(value)
        when "sdk"         then @sdk = scalar(value)
        when "sdk_version" then @sdk_version = scalar(value)
        when "wasm"        then @wasm = scalar(value)
        end
      end

      private def assign_permission(key : String, value : String)
        case key
        when "network"          then permissions.network = array(value)
        when "secrets"          then permissions.secrets = array(value)
        when "filesystem_read"  then permissions.filesystem_read = array(value)
        when "filesystem_write" then permissions.filesystem_write = array(value)
        when "shell"            then permissions.shell = boolean(value)
        when "model"            then permissions.model = boolean(value)
        end
      end

      private def assign_auth_provider(provider : AuthProviderDeclaration?, key : String, value : String)
        return unless p = provider
        case key
        when "id", "name" then p.id = scalar(value)
        when "title"      then p.title = scalar(value)
        end
      end

      private def assign_auth_flow(flow : AuthFlowDeclaration?, key : String, value : String)
        return unless f = flow
        case key
        when "id"   then f.id = scalar(value)
        when "kind" then f.kind = scalar(value)
        else             f.metadata[key] = scalar(value)
        end
      end

      private def assign_contribution(current : Contribution?, key : String, value : String)
        return unless c = current
        case key
        when "name", "id"  then c.name = scalar(value)
        when "title"       then c.title = scalar(value)
        when "description" then c.description = scalar(value)
        when "event"       then c.event = scalar(value); c.name = c.event || c.name
        when "entrypoint"  then c.entrypoint = scalar(value)
        end
      end

      private def scalar(value : String) : String
        value.strip.gsub(/^"|"$/, "")
      end

      private def boolean(value : String) : Bool
        value.strip == "true"
      end

      private def array(value : String) : Array(String)
        stripped = value.strip
        return [] of String unless stripped.starts_with?("[") && stripped.ends_with?("]")
        inner = stripped[1...-1]
        return [] of String if inner.strip.empty?
        inner.split(",").map { |v| scalar(v.strip) }
      end

      def validate(require_wasm : Bool = true)
        errors << "name is required" if name.empty?
        errors << "version is required" if version.empty?
        errors << "abi must be #{Cri::ABI_VERSION}" unless abi == Cri::ABI_VERSION
        all_contributions.each do |c|
          errors << "#{c.kind} name/id/event is required" if c.name.empty?
        end

        validate_auth_providers

        if executable?
          errors << "wasm is required for executable contributions" if wasm.nil? || wasm.try(&.empty?)
        end
        if wasm_path
          path = wasm_path.not_nil!
          root = File.expand_path(root_dir)
          unless path == root || path.starts_with?(root + File::SEPARATOR)
            errors << "wasm path must stay inside extension directory"
          end
          errors << "wasm file not found: #{path}" if require_wasm && !File.file?(path)
        end
      end

      private def validate_auth_providers
        provider_ids = Set(String).new
        auth_providers.each do |provider|
          errors << "auth provider id is required" if provider.id.empty?
          errors << "duplicate auth provider: #{provider.id}" if provider_ids.includes?(provider.id)
          provider_ids.add(provider.id)
          errors << "auth provider title is required: #{provider.id}" if provider.title.empty?

          flow_ids = Set(String).new
          provider.flows.each do |flow|
            errors << "auth flow id is required: #{provider.id}" if flow.id.empty?
            errors << "duplicate auth flow: #{provider.id}/#{flow.id}" if flow_ids.includes?(flow.id)
            flow_ids.add(flow.id)
            unless {"api_token", "oauth_device", "oauth_browser"}.includes?(flow.kind)
              errors << "unsupported auth flow kind: #{provider.id}/#{flow.id}"
            end
          end
          errors << "auth provider must declare a flow: #{provider.id}" if provider.flows.empty?
        end
      end

      private def executable? : Bool
        !tools.empty? || !commands.empty? || !hooks.empty? || !context_providers.empty? || !ui_status_items.empty? || !ui_panels.empty? || !ui_actions.empty?
      end

      def all_contributions : Array(Contribution)
        tools + commands + hooks + context_providers + ui_status_items + ui_panels + ui_actions
      end
    end
  end
end
