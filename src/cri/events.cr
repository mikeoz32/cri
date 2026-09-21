module Cri
  class Event
    getter name : String
    getter data : JSON::Any
    getter source : String?

    def initialize(@name : String, @data : JSON::Any = JSON.parse("{}"), @source : String? = nil)
    end
  end

  class EventBus
    alias Listener = Proc(Event, Nil)

    def initialize
      @listeners = {} of String => Array(Listener)
      @all_listeners = [] of Listener
    end

    def subscribe(name : String, &block : Event -> Nil)
      (@listeners[name] ||= [] of Listener) << block
    end

    def subscribe_all(&block : Event -> Nil)
      @all_listeners << block
    end

    def emit(event : Event)
      @listeners[event.name]?.try { |listeners| listeners.each { |listener| listener.call(event) } }
      @all_listeners.each { |listener| listener.call(event) }
    end
  end
end
