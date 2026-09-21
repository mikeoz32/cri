module Cri
  module Tui
    enum Mode
      Normal
      Insert
      Visual
      Command

      def label : String
        case self
        when .normal?  then "NORMAL"
        when .insert?  then "INSERT"
        when .visual?  then "VISUAL"
        when .command? then "COMMAND"
        else                "UNKNOWN"
        end
      end
    end

    enum Key
      Character
      Enter
      Escape
      Backspace
      Tab
      CtrlC
      CtrlD
      CtrlE
      CtrlU
      CtrlW
      CtrlY
      Up
      Down
      Left
      Right
    end

    struct KeyEvent
      getter key : Key
      getter value : String?

      def initialize(@key : Key, @value : String? = nil)
      end

      def self.character(value : String) : self
        new(Key::Character, value)
      end

      def token : String
        return value.not_nil! if key.character?
        case key
        when .enter?     then "enter"
        when .escape?    then "escape"
        when .backspace? then "backspace"
        when .tab?       then "tab"
        when .ctrl_c?    then "ctrl-c"
        when .ctrl_d?    then "ctrl-d"
        when .ctrl_e?    then "ctrl-e"
        when .ctrl_u?    then "ctrl-u"
        when .ctrl_w?    then "ctrl-w"
        when .ctrl_y?    then "ctrl-y"
        when .up?        then "up"
        when .down?      then "down"
        when .left?      then "left"
        when .right?     then "right"
        else                  "unknown"
        end
      end
    end
  end
end
