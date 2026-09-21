module Cri
  module Effects
    module UiSink
      abstract def notify(message : String, level : String)
      abstract def create_ui_buffer(id : String, content : String, owner : String) : String
      abstract def append_ui_buffer(id : String, content : String, owner : String) : String
      abstract def replace_ui_buffer(id : String, content : String, owner : String) : String
      abstract def set_ui_highlight(id : String, start : Int32, finish : Int32, group : String, owner : String) : String
      abstract def define_ui_style(group : String, foreground : Int32?, bold : Bool, underline : Bool, owner : String) : String
      abstract def open_ui_panel(id : String, buffer_id : String, title : String, position : String, focus : Bool, owner : String) : String
      abstract def focus_ui_panel(id : String, owner : String) : String
    end

    class Result
      include JSON::Serializable

      property ok : Bool
      property type : String
      property result : JSON::Any?
      property error : String?

      def initialize(@type : String, @ok : Bool, @result : JSON::Any? = nil, @error : String? = nil)
      end
    end
  end
end
