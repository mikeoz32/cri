module Cri
  module Tui
    abstract class Buffer
      getter id : String
      getter kind : String
      getter owner : String
      getter persistent : Bool

      def initialize(@id : String, @kind : String, @owner : String = "ui", @persistent : Bool = false)
      end

      abstract def lines : Array(String)
    end

    class TextBuffer < Buffer
      getter content : String
      getter events : EventBus?
      getter cursor : Int32
      getter cursor_revision : Int64
      getter mode : Mode
      getter masked : Bool
      getter selection_anchor : Int32?
      @highlights = [] of Highlight
      @selection_anchor : Int32? = nil
      @cursor_revision : Int64 = 0_i64

      def highlights : Array(Highlight)
        @highlights.dup
      end

      def highlight(start : Int32, finish : Int32, group : String)
        validate_highlight(start, finish, group)
        @highlights << Highlight.new(start, finish, group)
        emit_change
      end

      def set_highlights(regions : Array(Highlight))
        regions.each { |region| validate_highlight(region.start, region.finish, region.group) }
        @highlights = regions.dup
        emit_change
      end

      def clear_highlights
        @highlights.clear
        emit_change
      end

      def mode=(value : Mode)
        @mode = value
        @selection_anchor = nil unless value.visual?
        events.try do |bus|
          bus.emit(Event.new("buffer.mode_changed", JSON.parse({"buffer_id" => id, "mode" => value.label}.to_json), id))
        end
      end

      def cursor=(position : Int32)
        next_cursor = clamp_offset(position)
        @cursor_revision += 1 if next_cursor != @cursor
        @cursor = next_cursor
        events.try { |bus| bus.emit(Event.new("buffer.changed", source: id)) }
      end

      def begin_visual
        @selection_anchor = cursor
        self.mode = Mode::Visual
      end

      def selection_range : Range(Int32, Int32)?
        anchor = selection_anchor
        return nil unless anchor
        start = {anchor, cursor}.min
        finish = {anchor, cursor}.max + 1
        finish = content.size if finish > content.size
        return nil if start == finish
        start...finish
      end

      def selected_text : String
        range = selection_range
        return "" unless range
        content.chars[range.begin...range.end].join
      end

      def initialize(id : String, @content : String = "", owner : String = "ui", persistent : Bool = false, @events : EventBus? = nil, @mode : Mode = Mode::Normal, @masked : Bool = false)
        super(id, "text", owner, persistent)
        @cursor = @content.size.to_i32
      end

      def masked=(value : Bool)
        @masked = value
        emit_change
      end

      def lines : Array(String)
        content.split('\n', remove_empty: false)
      end

      def replace(@content : String)
        @highlights.clear
        @selection_anchor = nil
        @cursor = content.size.to_i32
        @cursor_revision += 1
        emit_change
      end

      def append(text : String)
        @content += text
        @cursor = content.size.to_i32
        @cursor_revision += 1
        emit_change
      end

      def append_line(text : String)
        append("#{text}\n")
      end

      def clear
        replace("")
      end

      def cursor_line_column : Tuple(Int32, Int32)
        line = 0
        column = 0
        content.each_char_with_index do |char, index|
          break if index >= cursor
          if char == '\n'
            line += 1
            column = 0
          else
            column += 1
          end
        end
        {line, column}
      end

      def move_vertical(delta : Int32)
        line, column = cursor_line_column
        lines = content.split('\n', remove_empty: false)
        target = line + delta
        target = 0 if target < 0
        last_line = lines.size.to_i32 - 1
        target = last_line if target > last_line
        target_column = column > lines[target].size ? lines[target].size.to_i32 : column
        self.cursor = lines.first(target).sum { |item| item.size + 1 }.to_i32 + target_column
      end

      def insert(text : String)
        position = clamp_offset(cursor)
        @highlights.clear unless text.empty?
        @content = content[0...position] + text + content[position..-1].to_s
        @cursor = position + text.size
        @cursor_revision += 1 unless text.empty?
        emit_change
      end

      def backspace
        return if cursor <= 0
        position = clamp_offset(cursor)
        return if position == 0
        @highlights.clear
        @content = content[0...position - 1] + content[position..-1].to_s
        @cursor = position - 1
        @cursor_revision += 1
        emit_change
      end

      private def validate_highlight(start : Int32, finish : Int32, group : String)
        raise ArgumentError.new("invalid highlight group") if group.empty?
        raise ArgumentError.new("invalid highlight range") unless 0 <= start && start < finish && finish <= content.size
      end

      private def clamp_offset(offset : Int32) : Int32
        value = offset < 0 ? 0 : offset
        value > content.size ? content.size : value
      end

      private def emit_change
        events.try do |bus|
          bus.emit(Event.new("buffer.changed", JSON.parse({"buffer_id" => id, "cursor" => cursor}.to_json), id))
        end
      end
    end

    class BufferStore
      getter buffers = {} of String => Buffer
      getter events : EventBus?

      def initialize(@events : EventBus? = nil)
      end

      def register(buffer : Buffer)
        raise "buffer already exists: #{buffer.id}" if buffers.has_key?(buffer.id)
        @buffers[buffer.id] = buffer
      end

      def text(id : String, content : String = "", owner : String = "ui", persistent : Bool = false, mode : Mode = Mode::Normal) : TextBuffer
        buffer = TextBuffer.new(id, content, owner, persistent, events, mode)
        register(buffer)
        buffer
      end

      def get(id : String) : Buffer
        buffers[id]? || raise "unknown buffer: #{id}"
      end

      def remove(id : String)
        @buffers.delete(id)
      end

      def includes?(id : String) : Bool
        buffers.has_key?(id)
      end

      def all : Array(Buffer)
        buffers.values
      end
    end
  end
end
