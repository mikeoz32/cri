module Cri
  class Config
    getter cwd : String
    getter extension_dirs : Array(String)
    getter grants : Permissions::GrantPolicy

    def initialize(@cwd : String, @extension_dirs : Array(String), @grants : Permissions::GrantPolicy)
    end

    def initialize(cwd : String = Dir.current, extension_dirs : Array(String)? = nil, grants : Permissions::GrantPolicy = Permissions::GrantPolicy.default)
      @cwd = cwd
      @extension_dirs = extension_dirs || self.class.default_extension_dirs(cwd)
      @grants = grants
    end

    def self.load(cwd : String = Dir.current) : self
      paths = [] of String
      if home = ENV["HOME"]?
        paths << File.join(home, ".config", "cri", "config.json")
      end
      paths << File.join(cwd, ".cri", "config.json")
      new(cwd, nil, Permissions::GrantPolicy.load(paths))
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
