module Cri
  module Tui
    struct PanelGeometry
      getter panel : Panel
      getter row : Int32
      getter column : Int32
      getter width : Int32
      getter height : Int32
      getter bottom : Bool

      def initialize(@panel : Panel, @row : Int32, @column : Int32, @width : Int32, @height : Int32, @bottom : Bool = false)
      end
    end

    # Full-terminal layout with an incremental terminal backend. The first
    # frame and resizes clear the alternate screen; normal updates redraw only
    # changed rows, preventing input flicker.
    class Renderer
      property workspace : Workspace
      getter buffers : BufferStore
      getter width : Int32
      getter height : Int32

      def initialize(@workspace : Workspace, @buffers : BufferStore, width : Int32? = nil, height : Int32? = nil, @theme : Theme = Theme.new)
        terminal_width, terminal_height = Terminal.dimensions
        @width = {(width || terminal_width), 1}.max
        @height = {(height || terminal_height), 5}.max
        @previous = [] of String
        @previous_width = 0
        @previous_height = 0
      end

      def resize(width : Int32, height : Int32)
        @width = {width, 1}.max
        @height = {height, 5}.max
      end

      def frame(styled : Bool = false) : Array(String)
        body_height = height - 4
        rows = [header(styled), divider]
        main = workspace.panels.all.select { |panel| panel.position == "main" }
        right = workspace.panels.all.select { |panel| panel.position == "right" }

        if right.empty? || width < 60
          rows.concat(render_stack(main + right, body_height, width, styled))
        else
          right_width = {width // 3, 24}.max
          main_width = {width - right_width - 3, 20}.max
          left_rows = render_stack(main, body_height, main_width, styled)
          right_rows = render_stack(right, body_height, right_width, styled)
          body_height.times do |index|
            rows << "#{pad(left_rows[index], main_width)} │ #{pad(right_rows[index], right_width)}"
          end
        end

        rows << divider
        rows << input_line(styled)
        rows.first(height)
      end

      def cursor_shape : String
        case current_mode
        when .normal?  then "\e[2 q" # steady block
        when .insert?  then "\e[6 q" # steady bar
        when .visual?  then "\e[2 q" # steady block
        when .command? then "\e[4 q" # steady underline
        else                "\e[2 q"
        end
      end

      # Returns a 1-indexed terminal position for the focused panel cursor.
      # A cursor outside the panel viewport is hidden until scrolling reveals it.
      def cursor_screen_position : Tuple(Int32, Int32)?
        panel = workspace.panels.focused
        return nil unless panel
        buffer = buffers.get(panel.buffer_id).as?(TextBuffer)
        return nil unless buffer
        geometry = panel_geometries.find { |item| item.panel.id == panel.id }
        return nil unless geometry

        if geometry.bottom
          return {geometry.row, {geometry.column + panel.prompt.size + buffer.cursor, width}.min}
        end

        cursor_line, cursor_column = buffer.cursor_line_column
        content_height = {geometry.height - 1, 0}.max
        panel.ensure_cursor_visible(buffers, content_height)
        start = panel.view_start(buffers, content_height)
        return nil unless cursor_line >= start && cursor_line < start + content_height
        {
          geometry.row + 1 + cursor_line - start,
          {geometry.column + cursor_column, geometry.column + geometry.width - 1}.min,
        }
      end

      # Returns changed 1-indexed row numbers. Kept public for regression
      # tests; render uses this same diff before writing to STDOUT.
      def changed_rows(current : Array(String) = frame(true)) : Array(Int32)
        full = @previous.empty? || @previous_width != width || @previous_height != height
        current.each_with_index.compact_map do |line, index|
          (full || @previous[index]? != line) ? (index + 1).to_i32 : nil
        end.to_a
      end

      def commit(rendered : Array(String) = frame(true))
        @previous = rendered
        @previous_width = width
        @previous_height = height
      end

      def render
        current = frame(true)
        rows = changed_rows(current)
        full = @previous.empty? || @previous_width != width || @previous_height != height

        print "\e[?25l"
        print "\e[H\e[2J" if full
        rows.each do |row|
          print "\e[#{row};1H#{current[row - 1]}\e[K"
        end
        position_cursor
        STDOUT.flush

        commit(current)
      end

      private def panel_geometries : Array(PanelGeometry)
        body_height = height - 4
        main = workspace.panels.all.select { |panel| panel.position == "main" }
        right = workspace.panels.all.select { |panel| panel.position == "right" }
        geometries = [] of PanelGeometry

        if right.empty? || width < 60
          geometries.concat(stack_geometries(main + right, 3, 1, width, body_height))
        else
          right_width = {width // 3, 24}.max
          main_width = {width - right_width - 3, 20}.max
          geometries.concat(stack_geometries(main, 3, 1, main_width, body_height))
          geometries.concat(stack_geometries(right, 3, main_width + 4, right_width, body_height))
        end

        workspace.panels.all.select { |panel| panel.position == "bottom" }.each do |panel|
          geometries << PanelGeometry.new(panel, height, 1, width, 1, true)
        end
        geometries
      end

      private def stack_geometries(panels : Array(Panel), row : Int32, column : Int32, panel_width : Int32, available_height : Int32) : Array(PanelGeometry)
        geometries = [] of PanelGeometry
        panels.each_with_index do |panel, index|
          allocation = available_height // panels.size
          allocation += available_height % panels.size if index == panels.size - 1
          geometries << PanelGeometry.new(panel, row, column, panel_width, allocation)
          row += allocation
        end
        geometries
      end

      private def position_cursor
        position = cursor_screen_position
        if position
          row, column = position
          print "\e[#{row};#{column}H#{cursor_shape}\e[?25h"
        end
      end

      private def current_mode : Mode
        panel = workspace.panels.focused
        panel.try { |item| buffers.get(item.buffer_id).as?(TextBuffer).try(&.mode) } || Mode::Normal
      end

      private def header(styled : Bool) : String
        value = " cri | #{current_mode.label} | #{workspace.status} "
        styled ? style(value, "accent") : fit(value, width)
      end

      private def divider : String
        "─" * width
      end

      private def render_stack(panels : Array(Panel), height : Int32, panel_width : Int32, styled : Bool) : Array(String)
        return Array.new(height, "") if panels.empty?
        lines = [] of String
        panels.each_with_index do |panel, index|
          allocation = height // panels.size
          allocation += height % panels.size if index == panels.size - 1
          next if allocation <= 0
          lines << (styled ? style("[ #{panel.title} ]", panel.focused ? "accent" : "comment") : "[ #{panel.title} ]")
          content = panel.render_lines(buffers, {allocation - 1, 0}.max, panel_width, styled ? @theme : nil)
          lines.concat(content)
          ({allocation - 1 - content.size, 0}.max).times { lines << "" }
        end
        lines.first(height) + Array.new({height - lines.size, 0}.max, "")
      end

      private def input_line(styled : Bool) : String
        panel = workspace.panels.all.find { |item| item.position == "bottom" }
        return "" unless panel
        buffer = buffers.get(panel.buffer_id).as(TextBuffer)
        prompt = styled ? style(panel.prompt, current_mode.command? ? "command" : "accent") : panel.prompt
        content = buffer.masked ? "•" * buffer.content.chars.size : buffer.content
        prompt + HighlightRenderer.line(content, 0, buffer.highlights, width - panel.prompt.size, styled ? @theme : nil)
      end

      private def style(value : String, group : String) : String
        colors = @theme[group]
        colors ? colors.ansi + fit(value, width) + "\e[0m" : fit(value, width)
      end

      private def pad(value : String, target_width : Int32) : String
        value + (" " * {target_width - visible_width(value), 0}.max)
      end

      private def visible_width(value : String) : Int32
        value.gsub(/\e\[[0-9; ]*m/, "").size.to_i32
      end

      private def fit(value : String, limit : Int32) : String
        safe = value.gsub(/[\x00-\x1f\x7f-\x9f]/, "")
        safe.size > limit ? safe[0, limit] : safe
      end
    end
  end
end
