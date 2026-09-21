module Cri
  module Tui
    class KeyBinding
      getter mode : Mode
      getter sequence : Array(String)
      getter action : String

      def initialize(@mode : Mode, @sequence : Array(String), @action : String)
        raise ArgumentError.new("key sequence is empty") if sequence.empty?
        raise ArgumentError.new("action is empty") if action.empty?
      end
    end

    enum KeyMatchKind
      None
      Prefix
      Action
    end

    struct KeyMatch
      getter kind : KeyMatchKind
      getter action : String?

      def initialize(@kind : KeyMatchKind, @action : String? = nil)
      end
    end

    # Declarative modal keymaps. It resolves key sequences only; action
    # semantics live in EventHandler or in EventBus subscribers.
    class Keymap
      getter bindings = [] of KeyBinding

      def initialize
        @pending = [] of String
        @pending_mode = nil.as(Mode?)
      end

      def bind(mode : Mode, keys : String | Array(String), action : String)
        sequence = keys.is_a?(String) ? parse(keys) : keys
        bindings.reject! { |binding| binding.mode == mode && binding.sequence == sequence }
        bindings << KeyBinding.new(mode, sequence, action)
      end

      def unbind(mode : Mode, keys : String | Array(String))
        sequence = keys.is_a?(String) ? parse(keys) : keys
        bindings.reject! { |binding| binding.mode == mode && binding.sequence == sequence }
      end

      def clear(mode : Mode? = nil)
        mode ? bindings.reject! { |binding| binding.mode == mode } : bindings.clear
        reset
      end

      def resolve(mode : Mode, event : KeyEvent) : KeyMatch
        reset if @pending_mode && @pending_mode != mode
        @pending_mode = mode
        @pending << event.token

        candidates = matching_bindings(mode, @pending)
        if candidates.empty?
          # A character wildcard is only valid for a one-key sequence.
          wildcard = @pending.size == 1 ? wildcard_binding(mode) : nil
          reset
          return wildcard ? KeyMatch.new(KeyMatchKind::Action, wildcard.action) : KeyMatch.new(KeyMatchKind::None)
        end

        exact = candidates.find { |binding| binding.sequence.size == @pending.size }
        has_longer = candidates.any? { |binding| binding.sequence.size > @pending.size }
        if exact && !has_longer
          action = exact.action
          reset
          KeyMatch.new(KeyMatchKind::Action, action)
        elsif exact
          KeyMatch.new(KeyMatchKind::Prefix)
        else
          KeyMatch.new(KeyMatchKind::Prefix)
        end
      end

      def reset
        @pending.clear
        @pending_mode = nil
      end

      private def parse(keys : String) : Array(String)
        keys.split.map { |key| key.downcase }
      end

      private def matching_bindings(mode : Mode, pending : Array(String)) : Array(KeyBinding)
        bindings.select do |binding|
          binding.mode == mode && binding.sequence.size >= pending.size && binding.sequence.first(pending.size) == pending
        end
      end

      private def wildcard_binding(mode : Mode) : KeyBinding?
        bindings.find { |binding| binding.mode == mode && binding.sequence == ["<char>"] }
      end
    end
  end
end
