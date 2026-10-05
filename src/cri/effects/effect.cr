module Cri
  module Effects
    class Effect
      include JSON::Serializable

      getter type : String
    end

    class HttpAuth
      include JSON::Serializable

      property secret : String
      @[JSON::Field(key: "as")]
      property scheme : String = "bearer"
    end

    class HttpRequestEffect < Effect
      property url : String
      property method : String = "GET"
      property headers : Hash(String, String) = {} of String => String
      property auth : HttpAuth?
      property body : RawJSON?
    end

    class FileReadEffect < Effect
      property path : String
    end

    class FilesystemListEffect < Effect
      property path : String = "."
    end

    class FileProposeEditEffect < Effect
    end

    class NotificationEffect < Effect
      property message : String?
      property level : String = "info"
    end

    class BufferCreateEffect < Effect
      property id : String?
      property content : String = ""
    end

    class BufferAppendEffect < Effect
      property id : String?
      property content : String?
    end

    class BufferReplaceEffect < Effect
      property id : String?
      property content : String?
    end

    class HighlightSetEffect < Effect
      property id : String?
      property group : String?
      property start : Int32?
      property finish : Int32?
    end

    class HighlightDefineEffect < Effect
      property group : String?
      property foreground : Int32?
      property bold : Bool = false
      property underline : Bool = false
    end

    class PanelOpenEffect < Effect
      property id : String?
      property buffer_id : String?
      property title : String?
      property position : String = "right"
      property focus : Bool = false
    end

    class PanelFocusEffect < Effect
      property id : String?
    end

    class StatusUpdateEffect < Effect
    end

    class ProviderRegisterEffect < Effect
      property id : String?
      property title : String?
      property api_type : String?
      property endpoint : String?
      property model : String = ""
      @[JSON::Field(key: "transport")]
      property transport_type : String = "http+sse"
      property auth_flows : Array(RawJSON) = [] of RawJSON
      property models : Array(RawJSON) = [] of RawJSON
    end

    class Effect
      use_json_discriminator "type", {
        "http.request"           => HttpRequestEffect,
        "file.read"              => FileReadEffect,
        "filesystem.list"        => FilesystemListEffect,
        "file.propose_edit"      => FileProposeEditEffect,
        "ui.notification"        => NotificationEffect,
        "ui.buffer.create"       => BufferCreateEffect,
        "ui.buffer.append"       => BufferAppendEffect,
        "ui.buffer.replace"      => BufferReplaceEffect,
        "ui.highlight.set"       => HighlightSetEffect,
        "ui.highlight.define"    => HighlightDefineEffect,
        "ui.panel.open"          => PanelOpenEffect,
        "ui.panel.focus"         => PanelFocusEffect,
        "ui.status_update"       => StatusUpdateEffect,
        "host.provider.register" => ProviderRegisterEffect,
      }
    end

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
      property result : RawJSON?
      property error : String?

      def initialize(@type : String, @ok : Bool, @result : RawJSON? = nil, @error : String? = nil)
      end
    end
  end
end
