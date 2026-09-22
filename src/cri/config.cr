require "json"

module Cri
  class Config
    getter cwd : String
    getter extension_dirs : Array(String)
    getter grants : Permissions::GrantPolicy
    getter provider_id : String?
    getter auth_flow_id : String?

    def initialize(@cwd : String, @extension_dirs : Array(String), @grants : Permissions::GrantPolicy, @provider_id : String? = nil, @auth_flow_id : String? = nil)
    end

    def initialize(cwd : String = Dir.current, extension_dirs : Array(String)? = nil, grants : Permissions::GrantPolicy = Permissions::GrantPolicy.default, provider_id : String? = nil, auth_flow_id : String? = nil)
      @cwd = cwd
      @extension_dirs = extension_dirs || self.class.default_extension_dirs(cwd)
      @grants = grants
      @provider_id = provider_id || ENV["CRI_PROVIDER"]?
      @auth_flow_id = auth_flow_id || ENV["CRI_AUTH_FLOW"]?
    end

    def self.load(cwd : String = Dir.current) : self
      paths = [] of String
      if home = ENV["HOME"]?
        paths << File.join(home, ".config", "cri", "config.json")
      end
      paths << File.join(cwd, ".cri", "config.json")
      config_path = paths.reverse_each.find { |path| File.exists?(path) }
      provider_id = nil
      auth_flow_id = nil
      if config_path
        begin
          config = JSON.parse(File.read(config_path))
          provider_id = config["provider"]?.try(&.as_s?) || config["provider_id"]?.try(&.as_s?)
          auth_flow_id = config["auth_flow"]?.try(&.as_s?) || config["auth_flow_id"]?.try(&.as_s?)
        rescue JSON::ParseException
        end
      end
      new(cwd, nil, Permissions::GrantPolicy.load(paths), provider_id, auth_flow_id)
    end

    def self.default_extension_dirs(cwd : String) : Array(String)
      dirs = [File.join(cwd, "extensions"), File.join(cwd, "examples", "extensions")]
      if home = ENV["HOME"]?
        dirs << File.join(home, ".config", "cri", "extensions")
      end
      dirs
    end

    private def default_extension_dirs(cwd : String)
      self.class.default_extension_dirs(cwd)
    end
  end
end
