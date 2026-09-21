module Cri
  module Tui
    class Panel
      getter id : String
      getter buffer_id : String
      getter title : String
      getter position : String
      getter events : EventBus?
      getter editable : Bool
      property focused : Bool
      property scroll : Int32
      property prompt : String

      def initialize(
        @id : String,
        @buffer_id : String,
        @title : String,
        @position : String = "main",
        @focused : Bool = false,
        @prompt : String = "",
        @events : EventBus? = nil,
        @editable : Bool = true,
      )
        @scroll = 0
        @last_cursor_revision = 0_i64
      end

      def ensure_cursor_visible(buffers : BufferStore, height : Int32)
        buffer = buffers.get(buffer_id).as?(TextBuffer)
        return unless buffer
        return if @last_cursor_revision == buffer.cursor_revision
        @last_cursor_revision = buffer.cursor_revision
        available = {height, 1}.max
        line, _ = buffer.cursor_line_column
        max_scroll = {buffer.lines.size - available, 0}.max
        start = {max_scroll - scroll, 0}.max

        if line < start
          @scroll = max_scroll - line
        elsif line >= start + available
          target_start = line - available + 1
          @scroll = max_scroll - target_start
        end
        @scroll = { {scroll, 0}.max, max_scroll }.min
      end

      def view_start(buffers : BufferStore, height : Int32) : Int32
        available = {height, 0}.max
        source = buffers.get(buffer_id).lines
        max_scroll = {source.size - available, 0}.max
        {max_scroll - scroll, 0}.max
      end

      def render_lines(buffers : BufferStore, height : Int32, width : Int32, theme : Theme? = nil) : Array(String)
        available = {height, 0}.max
        buffer = buffers.get(buffer_id)
        ensure_cursor_visible(buffers, available)
        source = buffer.lines
        start = view_start(buffers, available)
        offset = source.first(start).sum { |line| line.size + 1 }
        text_buffer = buffer.as?(TextBuffer)
        regions = text_buffer.try(&.highlights) || [] of Highlight
        selection = text_buffer.try(&.selection_range)
        source[start, available].map do |line|
          rendered = HighlightRenderer.line(line, offset, regions, width, theme, selection)
          offset += line.size + 1
          rendered
        end
      end

      def scroll_by(delta : Int32)
        @scroll = {@scroll + delta, 0}.max
        emit("panel.scrolled", {"scroll" => scroll})
      end

      def page_size : Int32
        10
      end

      private def emit(name : String, data : Hash(String, Int32))
        events.try { |bus| bus.emit(Event.new(name, JSON.parse(data.to_json), id)) }
      end
    end

    class PanelStore
      getter panels = {} of String => Panel

      def register(panel : Panel)
        raise "panel already exists: #{panel.id}" if panels.has_key?(panel.id)
        @panels[panel.id] = panel
      end

      def get(id : String) : Panel
        panels[id]? || raise "unknown panel: #{id}"
      end

      def all : Array(Panel)
        panels.values
      end

      def includes?(id : String) : Bool
        panels.has_key?(id)
      end

      def remove(id : String) : Panel?
        panels.delete(id)
      end

      def focused : Panel?
        panels.values.find(&.focused)
      end
    end
  end
end
