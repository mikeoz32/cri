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
        next_cursor = grapheme_boundary_at_or_before(position)
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
        finish = next_grapheme_offset({anchor, cursor}.max)
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

      def move_left
        self.cursor = previous_grapheme_offset(cursor)
      end

      def move_right
        self.cursor = next_grapheme_offset(cursor)
      end

      def move_vertical(delta : Int32)
        line, column = cursor_line_column
        lines = content.split('\n', remove_empty: false)
        target = line + delta
        target = 0 if target < 0
        last_line = lines.size.to_i32 - 1
        target = last_line if target > last_line
        source_line = lines[line]? || ""
        target_line = lines[target]? || ""
        target_column = offset_at_cell_column(target_line, cell_column(source_line, column))
        self.cursor = line_start_offset(target) + target_column
      end

      def move_line_start
        line, _column = cursor_line_column
        self.cursor = line_start_offset(line)
      end

      def move_first_nonblank
        line, _column = cursor_line_column
        text = lines[line]? || ""
        leading = 0
        text.each_grapheme do |grapheme|
          break unless grapheme.to_s.chars.all?(&.whitespace?)
          leading += grapheme.size
        end
        self.cursor = line_start_offset(line) + leading
      end

      def move_line_end
        line, _column = cursor_line_column
        text = lines[line]? || ""
        offsets = grapheme_offsets(text)
        last_grapheme = offsets.size > 1 ? offsets[-2] : 0
        self.cursor = line_start_offset(line) + last_grapheme
      end

      def move_document_start
        self.cursor = 0
      end

      def move_document_end
        line = lines.size.to_i32 - 1
        text = lines.last? || ""
        offsets = grapheme_offsets(text)
        last_grapheme = offsets.size > 1 ? offsets[-2] : 0
        self.cursor = line_start_offset(line) + last_grapheme
      end

      def move_word_forward
        clusters = graphemes
        index = grapheme_index_at_or_after(cursor, clusters)
        return if index >= clusters.size

        current_class = word_class(clusters[index])
        while index < clusters.size && word_class(clusters[index]) == current_class && current_class != :space
          index += 1
        end
        while index < clusters.size && word_class(clusters[index]) == :space
          index += 1
        end
        self.cursor = offset_for_grapheme(index, clusters)
      end

      def move_word_backward
        clusters = graphemes
        index = grapheme_index_at_or_after(cursor, clusters)
        index -= 1 if index >= clusters.size || offset_for_grapheme(index, clusters) >= cursor
        while index >= 0 && word_class(clusters[index]) == :space
          index -= 1
        end
        return if index < 0

        current_class = word_class(clusters[index])
        while index > 0 && word_class(clusters[index - 1]) == current_class
          index -= 1
        end
        self.cursor = offset_for_grapheme(index, clusters)
      end

      def move_word_end
        clusters = graphemes
        index = grapheme_index_at_or_after(cursor, clusters)
        while index < clusters.size && word_class(clusters[index]) == :space
          index += 1
        end
        return if index >= clusters.size

        current_class = word_class(clusters[index])
        while index + 1 < clusters.size && word_class(clusters[index + 1]) == current_class
          index += 1
        end
        self.cursor = offset_for_grapheme(index, clusters)
      end

      def insert(text : String)
        position = clamp_offset(cursor)
        @highlights.clear unless text.empty?
        @content = content[0...position] + text + content[position..-1].to_s
        @cursor = grapheme_boundary_at_or_after(position + text.size)
        @cursor_revision += 1 unless text.empty?
        emit_change
      end

      def backspace
        return if cursor <= 0
        position = clamp_offset(cursor)
        return if position == 0
        start = previous_grapheme_offset(position)
        @highlights.clear
        @content = content[0...start] + content[position..-1].to_s
        @cursor = start
        @cursor_revision += 1
        emit_change
      end

      private def graphemes : Array(String)
        content.each_grapheme.map(&.to_s).to_a
      end

      private def grapheme_offsets(text : String = content) : Array(Int32)
        offsets = [0_i32]
        offset = 0_i32
        text.each_grapheme do |grapheme|
          offset += grapheme.size
          offsets << offset
        end
        offsets
      end

      private def grapheme_boundary_at_or_before(position : Int32) : Int32
        target = clamp_offset(position)
        boundary = 0_i32
        grapheme_offsets.each do |offset|
          break if offset > target
          boundary = offset
        end
        boundary
      end

      private def grapheme_boundary_at_or_after(position : Int32) : Int32
        target = clamp_offset(position)
        grapheme_offsets.find { |offset| offset >= target } || content.size.to_i32
      end

      private def previous_grapheme_offset(position : Int32) : Int32
        target = clamp_offset(position)
        previous = 0_i32
        grapheme_offsets.each do |offset|
          break if offset >= target
          previous = offset
        end
        previous
      end

      private def next_grapheme_offset(position : Int32) : Int32
        target = clamp_offset(position)
        grapheme_offsets.find { |offset| offset > target } || content.size.to_i32
      end

      private def grapheme_index_at_or_after(position : Int32, clusters : Array(String)) : Int32
        offsets = grapheme_offsets
        offsets.index { |offset| offset >= position } || clusters.size
      end

      private def offset_for_grapheme(index : Int32, clusters : Array(String)) : Int32
        clusters.first(index).sum(&.size).to_i32
      end

      private def line_start_offset(line : Int32) : Int32
        lines.first(line).sum { |item| item.size + 1 }.to_i32
      end

      private def cell_column(text : String, codepoint_column : Int32) : Int32
        prefix = text.chars.first(codepoint_column).join
        CellWidth.of(prefix)
      end

      private def offset_at_cell_column(text : String, target_column : Int32) : Int32
        offset = 0_i32
        column = 0_i32
        text.each_grapheme do |grapheme|
          width = CellWidth.of(grapheme.to_s)
          break if column + width > target_column
          column += width
          offset += grapheme.size
        end
        offset
      end

      private def word_class(grapheme : String) : Symbol
        char = grapheme.chars.first?
        return :space unless char
        return :space if char.whitespace?
        return :keyword if char.letter? || char.number? || char == '_'
        :punctuation
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
