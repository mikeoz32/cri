module Cri
  module Tui
    # A workspace owns panels, focus and layout state. Buffers are owned by
    # UiRuntime and are referenced by panels through buffer_id.
    class Workspace
      getter id : String
      getter panels : PanelStore
      getter events : EventBus?
      getter focused_panel_id : String
      getter status : String
      getter buffer_exists : Proc(String, Bool)?

      def initialize(@id : String = "main", @panels : PanelStore = PanelStore.new, @events : EventBus? = nil, @buffer_exists : Proc(String, Bool)? = nil)
        @status = "ready"
        @focused_panel_id = ""
      end

      def status=(value : String)
        @status = value
        emit("workspace.changed", {"status" => value})
      end

      def focus(id : String)
        panels.get(id)
        panels.all.each { |panel| panel.focused = panel.id == id }
        @focused_panel_id = id
        events.try do |bus|
          bus.emit(Event.new("panel.focused", JSON.parse({"panel_id" => id, "workspace_id" => self.id}.to_json), id))
        end
      end

      # Directional focus for the current main/right/bottom layout. Bottom
      # panels are ordinary focusable views; only their geometry is special.
      def focus_direction(direction : String)
        available = panels.all
        return if available.empty?
        current = panels.focused || available.first
        content = available.select { |panel| panel.position != "bottom" }

        target = case direction
                 when "left"
                   content.find { |panel| panel.position == "main" }
                 when "right"
                   content.find { |panel| panel.position == "right" }
                 when "down"
                   current.position == "bottom" ? nil : available.find { |panel| panel.position == "bottom" }
                 when "up"
                   if current.position == "bottom"
                     content.find { |panel| panel.position == "main" } || content.first?
                   else
                     column = content.select { |panel| panel.position == current.position }
                     index = column.index { |panel| panel.id == current.id } || 0
                     column[index - 1]?
                   end
                 end
        focus(target.id) if target
      end

      def focus_next
        available = panels.all
        return if available.empty?
        index = available.index { |panel| panel.id == focused_panel_id } || -1
        focus(available[(index + 1) % available.size].id)
      end

      private def emit(name : String, data : Hash(String, String))
        events.try { |bus| bus.emit(Event.new(name, JSON.parse(data.to_json), id)) }
      end

      def add_panel(id : String, buffer_id : String, title : String, position : String = "right", focused : Bool = false, prompt : String = "", editable : Bool = true) : Panel
        if checker = buffer_exists
          raise "unknown buffer: #{buffer_id}" unless checker.call(buffer_id)
        end
        panel = Panel.new(id, buffer_id, title, position, false, prompt, events, editable)
        panels.register(panel)
        emit("workspace.changed", {"panel_id" => id})
        focus(id) if focused
        panel
      end

      def remove_panel(id : String) : Panel?
        removed = panels.remove(id)
        return nil unless removed

        if removed.focused
          replacement = panels.all.first?
          if replacement
            focus(replacement.id)
          else
            @focused_panel_id = ""
          end
        end
        emit("workspace.changed", {"panel_removed" => id})
        removed
      end
    end
  end
end
