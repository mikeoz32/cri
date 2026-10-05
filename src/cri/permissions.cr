module Cri
  module Permissions
    class ExtensionGrantConfig
      include JSON::Serializable

      property enabled : Bool?
      property network : Array(String) = [] of String
      property secrets : Array(String) = [] of String
      property filesystem_read : Array(String) = [] of String
      property filesystem_write : Array(String) = [] of String
      property shell : Bool = false
      property model : Bool = false

      def to_grant_set : GrantSet
        GrantSet.new(network, secrets, filesystem_read, filesystem_write, shell, model)
      end
    end

    class GrantPolicyConfig
      include JSON::Serializable

      property extensions : Hash(String, ExtensionGrantConfig) = {} of String => ExtensionGrantConfig
    end

    enum EffectKind
      HttpRequest
      SecretUse
      FileRead
      FileEditProposal
      Notification
      StatusUpdate
      ToolCall
      ModelCall
    end

    class Request
      property network : Array(String)
      property secrets : Array(String)
      property filesystem_read : Array(String)
      property filesystem_write : Array(String)
      property shell : Bool
      property model : Bool

      def initialize(@network = [] of String, @secrets = [] of String, @filesystem_read = [] of String, @filesystem_write = [] of String, @shell = false, @model = false)
      end
    end

    class GrantSet < Request
      def self.default_dev : self
        # Safe default: no shell/model/fs write, no secrets, no network.
        new
      end

      def self.from_json(value : JSON::Any) : self
        ExtensionGrantConfig.from_json(value.to_json).to_grant_set
      end

      def allows_network?(url : String, requested : Request) : Bool
        uri = URI.parse(url)
        return false unless uri.scheme && uri.host
        network_allowed?(uri, requested.network) && network_allowed?(uri, network)
      rescue
        false
      end

      def allows_secret?(name : String, requested : Request) : Bool
        requested.secrets.includes?(name) && secrets.includes?(name)
      end

      def allows_file_read?(path : String, requested : Request, base : String? = nil) : Bool
        path_allowed?(path, requested.filesystem_read, base: base) && path_allowed?(path, filesystem_read, base: base)
      end

      def allows_file_write?(path : String, requested : Request) : Bool
        path_allowed?(path, requested.filesystem_write, create: true) && path_allowed?(path, filesystem_write, create: true)
      end

      private def network_allowed?(target : URI, patterns : Array(String)) : Bool
        patterns.any? do |pattern|
          scope = URI.parse(pattern)
          next false unless scope.scheme == target.scheme && scope.host && target.host
          next false unless host_allowed?(target.host.not_nil!, scope.host.not_nil!)
          next false if scope.port && scope.port != target.port

          scope_path = scope.path
          scope_path = "/" if scope_path.empty?
          target_path = target.path.empty? ? "/" : target.path
          target_path == scope_path || target_path.starts_with?(scope_path.ends_with?("/") ? scope_path : scope_path + "/")
        rescue
          false
        end
      end

      private def host_allowed?(target : String, scope : String) : Bool
        if scope.starts_with?("*.")
          suffix = scope[1..-1]
          target.ends_with?(suffix) && target != suffix[1..-1]
        else
          target == scope
        end
      end

      private def path_allowed?(path : String, roots : Array(String), create : Bool = false, base : String? = nil) : Bool
        PathSecurity.allowed?(path, roots, create, base)
      end
    end

    class GrantPolicy
      getter extensions = {} of String => GrantSet
      getter disabled = {} of String => Bool

      def self.default : self
        new
      end

      def self.load(paths : Array(String)) : self
        policy = new
        paths.each do |path|
          next unless File.file?(path)

          begin
            policy.merge(GrantPolicyConfig.from_json(File.read(path)))
          rescue ex
            policy.errors << "#{path}: #{ex.message || ex.class.name}"
          end
        end
        policy
      end

      getter errors = [] of String

      def for_extension(name : String) : GrantSet
        extensions[name]? || GrantSet.default_dev
      end

      def enabled?(name : String) : Bool
        !disabled.has_key?(name)
      end

      def merge_json(root : JSON::Any)
        merge(GrantPolicyConfig.from_json(root.to_json))
      end

      def merge(config : GrantPolicyConfig)
        config.extensions.each do |name, entry|
          if entry.enabled == false
            disabled[name] = true
            extensions.delete(name)
          else
            disabled.delete(name)
            extensions[name] = entry.to_grant_set
          end
        end
      end
    end
  end
end
