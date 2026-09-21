module Cri
  module Permissions
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
        object = value.as_h
        new(
          network: string_array(object["network"]?),
          secrets: string_array(object["secrets"]?),
          filesystem_read: string_array(object["filesystem_read"]?),
          filesystem_write: string_array(object["filesystem_write"]?),
          shell: object["shell"]?.try(&.as_bool) || false,
          model: object["model"]?.try(&.as_bool) || false
        )
      end

      private def self.string_array(value : JSON::Any?) : Array(String)
        value ? value.as_a.map(&.as_s) : [] of String
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

      def allows_file_read?(path : String, requested : Request) : Bool
        path_allowed?(path, requested.filesystem_read) && path_allowed?(path, filesystem_read)
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

      private def path_allowed?(path : String, roots : Array(String), create : Bool = false) : Bool
        PathSecurity.allowed?(path, roots, create)
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
          policy.merge_json(JSON.parse(File.read(path)))
        rescue ex
          policy.errors << "#{path}: #{ex.message || ex.class.name}"
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
        root["extensions"]?.try do |entries|
          entries.as_h.each do |name, value|
            if value["enabled"]?.try(&.as_bool) == false
              disabled[name] = true
              extensions.delete(name)
            else
              disabled.delete(name)
              extensions[name] = GrantSet.from_json(value)
            end
          end
        end
      end
    end
  end
end
