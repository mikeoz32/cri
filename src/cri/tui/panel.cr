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

      def ensure_cursor_visible(buffers : BufferStore, height : Int32, width : Int32 = 80)
        buffer = buffers.get(buffer_id).as?(TextBuffer)
        return unless buffer
        return if @last_cursor_revision == buffer.cursor_revision
        @last_cursor_revision = buffer.cursor_revision
        available = {height, 1}.max
        visual = visual_lines(buffers, width)
        return if visual.empty?
        cursor = cursor_visual_line(buffers, width)
        max_scroll = {visual.size - available, 0}.max
        start = {max_scroll - scroll, 0}.max

        if cursor < start
          @scroll = max_scroll - cursor
        elsif cursor >= start + available
          target_start = cursor - available + 1
          @scroll = max_scroll - target_start
        end
        @scroll = { {scroll, 0}.max, max_scroll }.min
      end

      def view_start(buffers : BufferStore, height : Int32, width : Int32 = 80) : Int32
        available = {height, 0}.max
        buffer = buffers.get(buffer_id)
        source_max = {buffer.lines.size - available, 0}.max
        source_start = {source_max - scroll, 0}.max
        visual = visual_lines(buffers, width)
        visual.index { |entry| entry[2] == source_start && entry[3] == 0 } || visual.size
      end

      def cursor_visual_line(buffers : BufferStore, width : Int32) : Int32
        buffer = buffers.get(buffer_id).as?(TextBuffer)
        return 0 unless buffer
        cursor_line, cursor_column = buffer.cursor_line_column
        visual = visual_lines(buffers, width)
        index = visual.index { |entry| entry[2] == cursor_line && cursor_column >= entry[3] && cursor_column <= entry[3] + entry[0].size }
        index || {visual.size - 1, 0}.max
      end

      def render_lines(buffers : BufferStore, height : Int32, width : Int32, theme : Theme? = nil) : Array(String)
        available = {height, 0}.max
        buffer = buffers.get(buffer_id)
        ensure_cursor_visible(buffers, available, width)
        source = visual_lines(buffers, width)
        start = view_start(buffers, available, width)
        text_buffer = buffer.as?(TextBuffer)
        regions = text_buffer.try(&.highlights) || [] of Highlight
        selection = text_buffer.try(&.selection_range)
        source[start, available].map do |entry|
          HighlightRenderer.line(entry[0], entry[1], regions, width, theme, selection)
        end
      end

      def scroll_by(delta : Int32)
        @scroll = {@scroll + delta, 0}.max
        emit("panel.scrolled", {"scroll" => scroll})
      end

      def page_size : Int32
        10
      end

      # Entries contain the wrapped text, its absolute highlight offset, the
      # source line, and the source-column where the wrapped segment starts.
      private def visual_lines(buffers : BufferStore, width : Int32) : Array(Tuple(String, Int32, Int32, Int32))
        limit = {width, 1}.max
        buffer = buffers.get(buffer_id)
        entries = [] of Tuple(String, Int32, Int32, Int32)
        offset = 0_i32
        buffer.lines.each_with_index do |line, source_line|
          chars = line.chars
          if chars.empty?
            entries << {"", offset, source_line.to_i32, 0_i32}
          else
            start = 0
            while start < chars.size
              finish = {start + limit, chars.size}.min
              entries << {chars[start...finish].join, offset + start, source_line.to_i32, start.to_i32}
              start = finish
            end
          end
          offset += line.size + 1
        end
        entries
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
