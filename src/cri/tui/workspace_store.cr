module Cri
  module Tui
    class WorkspaceStore
      getter workspaces = {} of String => Workspace
      getter active_id : String

      def initialize
        @active_id = ""
      end

      def register(workspace : Workspace)
        raise "workspace already exists: #{workspace.id}" if workspaces.has_key?(workspace.id)
        @workspaces[workspace.id] = workspace
        @active_id = workspace.id if @active_id.empty?
      end

      def get(id : String) : Workspace
        workspaces[id]? || raise "unknown workspace: #{id}"
      end

      def active : Workspace
        get(active_id)
      end

      def activate(id : String)
        get(id)
        @active_id = id
      end

      def remove(id : String)
        raise "cannot remove active workspace" if id == active_id
        @workspaces.delete(id)
      end

      def all : Array(Workspace)
        workspaces.values
      end
    end
  end
end
