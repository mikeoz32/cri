module Cri
  class SessionStore
    getter root : Path

    def initialize(workspace : String = Dir.current)
      @root = Path[workspace, ".cri", "sessions"]
    end

    def current : Session?
      return nil unless File.exists?(current_index)
      id = File.read(current_index).strip
      return nil if id.empty?
      load(id)
    rescue
      nil
    end

    def load(id : String) : Session?
      return nil unless safe_id?(id)
      path = @root / "#{id}.json"
      return nil unless File.exists?(path)
      Session.from_json(JSON.parse(File.read(path)))
    rescue
      nil
    end

    def list : Array(Session)
      return [] of Session unless Dir.exists?(@root)
      Dir.glob((@root / "*.json").to_s).compact_map do |path|
        begin
          Session.from_json(JSON.parse(File.read(path)))
        rescue
          nil
        end
      end.sort_by(&.id)
    end

    def save(session : Session) : Nil
      Dir.mkdir_p(@root)
      path = @root / "#{session.id}.json"
      temporary = @root / ".#{session.id}.#{Random::Secure.hex(6)}.tmp"
      File.write(temporary, session.to_json_any.to_json)
      File.chmod(temporary, 0o600)
      File.rename(temporary, path)
      File.chmod(path, 0o600)
      File.write(current_index, session.id)
      File.chmod(current_index, 0o600)
    ensure
      File.delete(temporary) if temporary && File.exists?(temporary)
    end

    private def current_index : Path
      @root.parent / "current-session"
    end

    private def safe_id?(id : String) : Bool
      id.matches?(/\A[a-f0-9]{16}\z/)
    end
  end
end
