require "json"

module Cri
  class Config
    getter cwd : String
    getter extension_dirs : Array(String)
    getter grants : Permissions::GrantPolicy
    getter provider_id : String?

    def initialize(@cwd : String, @extension_dirs : Array(String), @grants : Permissions::GrantPolicy, @provider_id : String? = nil)
    end

    def initialize(cwd : String = Dir.current, extension_dirs : Array(String)? = nil, grants : Permissions::GrantPolicy = Permissions::GrantPolicy.default, provider_id : String? = nil)
      @cwd = cwd
      @extension_dirs = extension_dirs || self.class.default_extension_dirs(cwd)
      @grants = grants
      @provider_id = provider_id || ENV["CRI_PROVIDER"]?
    end

    def self.load(cwd : String = Dir.current) : self
      paths = [] of String
      if home = ENV["HOME"]?
        paths << File.join(home, ".config", "cri", "config.json")
      end
      paths << File.join(cwd, ".cri", "config.json")
      provider_id = paths.reverse_each
        .find { |path| File.exists?(path) }
        .try do |path|
          JSON.parse(File.read(path))["provider"]?.try(&.as_s?) || JSON.parse(File.read(path))["provider_id"]?.try(&.as_s?)
        rescue JSON::ParseException
          nil
        end
      new(cwd, nil, Permissions::GrantPolicy.load(paths), provider_id)
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
