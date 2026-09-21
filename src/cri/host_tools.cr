module Cri
  class ReadFileTool < Tool
    getter cwd : String

    def initialize(cwd : String)
      @cwd = File.realpath(cwd)
      super("builtin.read_file", "Read a file inside the project")
    end

    def call(input : JSON::Any) : ToolResult
      path = input["path"].as_s
      full_path = safe_path(path)
      return ToolResult.new(false, nil, "path is outside project: #{path}") unless full_path
      ToolResult.new(true, JSON.parse({"path" => path, "content" => File.read(full_path)}.to_json))
    rescue ex
      ToolResult.new(false, nil, ex.message || ex.class.name)
    end

    private def safe_path(path : String) : String?
      candidate = PathSecurity.resolve_existing(path, cwd)
      candidate if candidate && PathSecurity.within?(candidate, cwd)
    end
  end

  class ListFilesTool < Tool
    getter cwd : String

    def initialize(cwd : String)
      @cwd = File.realpath(cwd)
      super("builtin.list_files", "List project files")
    end

    def call(input : JSON::Any) : ToolResult
      relative = input["path"]?.try(&.as_s) || "."
      full_path = PathSecurity.resolve_existing(relative, cwd)
      return ToolResult.new(false, nil, "path is outside project: #{relative}") unless full_path && PathSecurity.within?(full_path, cwd)
      return ToolResult.new(false, nil, "not a directory: #{relative}") unless Dir.exists?(full_path)

      files = Dir.children(full_path).sort.reject { |name| name.starts_with?(".") }
      ToolResult.new(true, JSON.parse({"path" => relative, "entries" => files}.to_json))
    rescue ex
      ToolResult.new(false, nil, ex.message || ex.class.name)
    end
  end
end
