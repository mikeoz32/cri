module Cri
  module Tui
    # Half-open Unicode codepoint offsets, matching TextBuffer#cursor.
    struct Highlight
      getter start : Int32
      getter finish : Int32
      getter group : String

      def initialize(@start : Int32, @finish : Int32, @group : String)
      end
    end

    struct Style
      getter foreground : Int32?
      getter bold : Bool
      getter underline : Bool

      def initialize(@foreground : Int32? = nil, @bold = false, @underline = false)
        if color = foreground
          raise ArgumentError.new("color must be 0..255") unless (0..255).includes?(color)
        end
      end

      def ansi : String
        codes = [] of String
        codes << "38;5;#{foreground}" if foreground
        codes << "1" if bold
        codes << "4" if underline
        codes.empty? ? "\e[0m" : "\e[0;#{codes.join(';')}m"
      end
    end

    class Theme
      def initialize
        @groups = {
          "error"     => Style.new(196, bold: true),
          "comment"   => Style.new(244),
          "keyword"   => Style.new(75, bold: true),
          "accent"    => Style.new(81),
          "selection" => Style.new(231, bold: true),
        }
      end

      def define(group : String, style : Style)
        @groups[group] = style
      end

      def [](group : String) : Style?
        @groups[group]?
      end
    end

    module HighlightRenderer
      # Sanitize before emitting styles. Raw buffer text never supplies ANSI.
      def self.line(text : String, offset : Int32, regions : Array(Highlight), width : Int32, theme : Theme?, selection : Range(Int32, Int32)? = nil) : String
        return "" if width <= 0
        String.build do |output|
          visible = 0
          active : String? = nil
          text.each_char_with_index do |char, index|
            next if char.ord < 32 || (127..159).includes?(char.ord)
            break if visible >= width
            absolute_index = offset + index
            selection_style = selection.try { |range| theme.try { |colors| colors["selection"] if range.includes?(absolute_index) } }
            region = regions.reverse.find { |item| item.start <= absolute_index && absolute_index < item.finish }
            style = selection_style || region.try { |item| theme.try { |colors| colors[item.group] } }
            ansi = style.try(&.ansi)
            if ansi != active
              output << (ansi || "\e[0m")
              active = ansi
            end
            output << char
            visible += 1
          end
          output << "\e[0m" if active
        end
      end
    end
  end
end
