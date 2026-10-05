module Cri
  module Tui
    @[Link("c")]
    lib LibCWidth
      fun setlocale(category : Int32, locale : UInt8*) : UInt8*
      fun wcwidth(codepoint : Int32) : Int32
    end

    # Approximate terminal cell widths for Unicode grapheme clusters. Crystal's
    # String#size counts codepoints, while terminals allocate cells to rendered
    # graphemes such as emoji sequences and East Asian wide characters.
    module CellWidth
      @@locale_initialized = false
      @@locale_mutex = Mutex.new

      def self.of(char : Char) : Int32
        cluster_width(char.to_s)
      end

      def self.of(text : String) : Int32
        width = 0
        text.each_grapheme { |cluster| width += cluster_width(cluster.to_s) }
        width
      end

      private def self.cluster_width(cluster : String) : Int32
        ensure_locale
        codepoints = cluster.chars.map(&.ord)

        return 2 if keycap?(codepoints) || regional_pair?(codepoints)

        text_presentation = codepoints.includes?(0xFE0E)
        emoji_sequence = codepoints.includes?(0xFE0F) || codepoints.includes?(0x200D) ||
                         codepoints.any? { |codepoint| emoji_modifier?(codepoint) }

        unless text_presentation
          return 2 if emoji_sequence && codepoints.any? { |codepoint| emoji?(codepoint) }
        end

        codepoints.sum { |codepoint| codepoint_width(codepoint) }
      end

      private def self.control?(codepoint : Int32) : Bool
        codepoint < 32 || (127..159).includes?(codepoint)
      end

      private def self.codepoint_width(codepoint : Int32) : Int32
        return 0 if control?(codepoint)
        width = LibCWidth.wcwidth(codepoint)
        return width if width >= 0

        char = codepoint.chr
        return 0 if char.mark? || emoji_modifier?(codepoint)
        east_asian_wide?(codepoint) ? 2 : 1
      end

      private def self.ensure_locale
        return if @@locale_initialized
        @@locale_mutex.synchronize do
          unless @@locale_initialized
            LibCWidth.setlocale(0, "".to_unsafe)
            @@locale_initialized = true
          end
        end
      end

      private def self.keycap?(codepoints : Array(Int32)) : Bool
        codepoints.includes?(0x20E3)
      end

      private def self.regional_pair?(codepoints : Array(Int32)) : Bool
        codepoints.count { |codepoint| (0x1F1E6..0x1F1FF).includes?(codepoint) } >= 2
      end

      private def self.emoji_modifier?(codepoint : Int32) : Bool
        (0x1F3FB..0x1F3FF).includes?(codepoint)
      end

      private def self.emoji?(codepoint : Int32) : Bool
        (0x1F000..0x1FAFF).includes?(codepoint) ||
          (0x2600..0x27FF).includes?(codepoint) ||
          (0x2300..0x23FF).includes?(codepoint) ||
          (0x2B00..0x2BFF).includes?(codepoint)
      end

      private def self.east_asian_wide?(codepoint : Int32) : Bool
        (0x1100..0x115F).includes?(codepoint) ||
          (0x2329..0x232A).includes?(codepoint) ||
          ((0x2E80..0xA4CF).includes?(codepoint) && codepoint != 0x303F) ||
          (0xAC00..0xD7A3).includes?(codepoint) ||
          (0xF900..0xFAFF).includes?(codepoint) ||
          (0xFE10..0xFE19).includes?(codepoint) ||
          (0xFE30..0xFE6F).includes?(codepoint) ||
          (0xFF00..0xFF60).includes?(codepoint) ||
          (0xFFE0..0xFFE6).includes?(codepoint) ||
          (0x20000..0x3FFFD).includes?(codepoint)
      end
    end

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
          codepoint_index = 0
          text.each_grapheme do |grapheme|
            cluster = grapheme.to_s
            cluster_size = cluster.size
            visible_cluster = cluster.each_char.reject { |char| char.ord < 32 || (127..159).includes?(char.ord) }.join
            absolute_index = offset + codepoint_index
            codepoint_index += cluster_size
            next if visible_cluster.empty?
            char_width = CellWidth.of(visible_cluster)
            break if visible + char_width > width
            selection_style = selection.try { |range| theme.try { |colors| colors["selection"] if range.includes?(absolute_index) } }
            region = regions.reverse.find { |item| item.start <= absolute_index && absolute_index < item.finish }
            style = selection_style || region.try { |item| theme.try { |colors| colors[item.group] } }
            ansi = style.try(&.ansi)
            if ansi != active
              output << (ansi || "\e[0m")
              active = ansi
            end
            output << visible_cluster
            visible += char_width
          end
          output << "\e[0m" if active
        end
      end
    end
  end
end
