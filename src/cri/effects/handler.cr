module Cri
  module Effects
    class Handler
      DEFAULT_HTTP_CONNECT_TIMEOUT = 10.seconds
      DEFAULT_HTTP_READ_TIMEOUT    = 30.seconds
      DEFAULT_HTTP_RESPONSE_BYTES  = 4_i64 * 1024_i64 * 1024_i64
      MAX_HTTP_REQUEST_BYTES       = 1_i64 * 1024_i64 * 1024_i64
      MAX_SESSION_STATE_BYTES      = 1_i64 * 1024_i64 * 1024_i64

      getter grants : Permissions::GrantSet
      getter requested : Permissions::Request
      getter ui_sink : UiSink?
      getter ui_owner : String?
      getter capabilities : API::CapabilityBroker
      getter actor : String
      getter provider_sink : Proc(JSON::Any, Nil)?
      getter workspace_root : String
      getter session : Session?
      getter events : EventBus

      def initialize(
        @grants : Permissions::GrantSet,
        @requested : Permissions::Request,
        @http_connect_timeout : Time::Span = DEFAULT_HTTP_CONNECT_TIMEOUT,
        @http_read_timeout : Time::Span = DEFAULT_HTTP_READ_TIMEOUT,
        @max_http_response_bytes : Int64 = DEFAULT_HTTP_RESPONSE_BYTES,
        @ui_sink : UiSink? = nil,
        @ui_owner : String? = nil,
        @capabilities : API::CapabilityBroker = API::CapabilityBroker.deny_all,
        @actor : String = "host",
        @provider_sink : Proc(JSON::Any, Nil)? = nil,
        @workspace_root : String = Dir.current,
        @session : Session? = nil,
        @events : EventBus = EventBus.new,
      )
      end

      def handle(effect : Effect) : Result
        case effect
        when HttpRequestEffect     then handle_http(effect)
        when FileReadEffect        then handle_file_read(effect)
        when FilesystemListEffect  then handle_filesystem_list(effect)
        when FileProposeEditEffect then result(effect, true, {"accepted" => false, "message" => "edit proposal recorded; apply flow not implemented yet"})
        when SessionStateGetEffect then handle_session_state_get(effect)
        when SessionStateSetEffect then handle_session_state_set(effect)
        when NotificationEffect    then handle_notification(effect)
        when BufferCreateEffect    then handle_buffer_create(effect)
        when BufferAppendEffect    then handle_buffer_mutation(effect, "append")
        when BufferReplaceEffect   then handle_buffer_mutation(effect, "replace")
        when HighlightSetEffect    then handle_highlight_set(effect)
        when HighlightDefineEffect then handle_highlight_define(effect)
        when PanelOpenEffect       then handle_panel_open(effect)
        when PanelFocusEffect      then handle_panel_focus(effect)
        when StatusUpdateEffect    then result(effect, true, {"updated" => true})
        when ProviderRegisterEffect
          sink = provider_sink || raise "provider registration is not available in this host context"
          sink.call(JSON.parse(effect.to_json))
          result(effect, true, {"registered" => true})
        else
          result(effect, false, nil, "unsupported effect type")
        end
      rescue ex
        Result.new(effect.type, false, nil, ex.message || ex.class.name)
      end

      def handle(effect : JSON::Any) : Result
        handle(Effect.from_json(effect.to_json))
      rescue ex : JSON::SerializableError | JSON::ParseException
        Result.new(effect["type"]?.try(&.as_s?) || "unknown", false, nil, ex.message || "unsupported effect type")
      end

      private def result(effect : Effect, ok : Bool, value : T, error : String? = nil) : Result forall T
        Result.new(effect.type, ok, RawJSON.new(value.to_json), error)
      end

      private def result(effect : Effect, ok : Bool, value : Nil, error : String? = nil) : Result
        Result.new(effect.type, ok, nil, error)
      end

      private def handle_notification(effect : NotificationEffect) : Result
        type = effect.type
        message = effect.message
        level = effect.level
        return result(effect, false, nil, "ui.notification requires a message") unless message
        return result(effect, false, nil, "invalid ui.notification level") unless {"info", "success", "warning", "error"}.includes?(level)
        return result(effect, false, nil, "ui.notification message is too long") if message.bytesize > 16_i64 * 1024_i64

        return result(effect, false, nil, "capability approval denied") unless authorize("ui.notification", level, "Show a notification")
        ui_sink.try(&.notify(message, level))
        result(effect, true, {"shown" => true, "level" => level})
      end

      private def handle_buffer_create(effect : BufferCreateEffect) : Result
        type = effect.type
        id = effect.id
        content = effect.content
        owner = ui_owner
        return result(effect, false, nil, "ui.buffer.create requires an extension owner") unless owner
        return result(effect, false, nil, "ui.buffer.create requires an id") unless id
        return result(effect, false, nil, "invalid ui.buffer.create id") unless id.matches?(/^[A-Za-z0-9._:-]{1,128}$/)
        return result(effect, false, nil, "ui.buffer.create content is too long") if content.bytesize > 4_i64 * 1024_i64 * 1024_i64
        return result(effect, false, nil, "capability approval denied") unless authorize("ui.buffer.create", id, "Create a UI buffer")
        return result(effect, false, nil, "UI sink is unavailable") unless sink = ui_sink

        buffer_id = sink.create_ui_buffer(id, content, owner)
        result(effect, true, {"buffer_id" => buffer_id, "owner" => owner})
      rescue ex
        result(effect, false, nil, ex.message || ex.class.name)
      end

      private def handle_buffer_mutation(effect : BufferAppendEffect | BufferReplaceEffect, operation : String) : Result
        type = effect.type
        id = effect.id
        content = effect.content
        owner = ui_owner
        return result(effect, false, nil, "#{type} requires an extension owner") unless owner
        return result(effect, false, nil, "#{type} requires an id") unless id
        return result(effect, false, nil, "#{type} requires content") unless content
        return result(effect, false, nil, "invalid #{type} id") unless id.matches?(/^[A-Za-z0-9._:-]{1,128}$/)
        return result(effect, false, nil, "#{type} content is too long") if content.bytesize > 4_i64 * 1024_i64 * 1024_i64
        return result(effect, false, nil, "capability approval denied") unless authorize("ui.buffer.#{operation}", id, "Modify a UI buffer")
        return result(effect, false, nil, "UI sink is unavailable") unless sink = ui_sink

        buffer_id = operation == "append" ? sink.append_ui_buffer(id, content, owner) : sink.replace_ui_buffer(id, content, owner)
        result(effect, true, {"buffer_id" => buffer_id})
      rescue ex
        result(effect, false, nil, ex.message || ex.class.name)
      end

      private def handle_highlight_set(effect : HighlightSetEffect) : Result
        type = effect.type
        id = effect.id
        group = effect.group
        start = effect.start
        finish = effect.finish
        owner = ui_owner
        return result(effect, false, nil, "ui.highlight.set requires an extension owner") unless owner
        return result(effect, false, nil, "ui.highlight.set requires an id") unless id
        return result(effect, false, nil, "ui.highlight.set requires a group") unless group
        return result(effect, false, nil, "ui.highlight.set requires start and finish") unless start && finish
        return result(effect, false, nil, "invalid ui.highlight.set id") unless id.matches?(/^[A-Za-z0-9._:-]{1,128}$/)
        return result(effect, false, nil, "invalid ui.highlight.set group") unless group.matches?(/^[A-Za-z0-9._:-]{1,64}$/)
        return result(effect, false, nil, "invalid ui.highlight.set range") unless start >= 0 && finish > start
        return result(effect, false, nil, "capability approval denied") unless authorize("ui.highlight.set", id, "Set UI highlighting")
        return result(effect, false, nil, "UI sink is unavailable") unless sink = ui_sink

        buffer_id = sink.set_ui_highlight(id, start, finish, group, owner)
        result(effect, true, {"buffer_id" => buffer_id})
      rescue ex
        result(effect, false, nil, ex.message || ex.class.name)
      end

      private def handle_highlight_define(effect : HighlightDefineEffect) : Result
        type = effect.type
        group = effect.group
        foreground = effect.foreground
        bold = effect.bold
        underline = effect.underline
        owner = ui_owner
        return result(effect, false, nil, "ui.highlight.define requires an extension owner") unless owner
        return result(effect, false, nil, "ui.highlight.define requires a group") unless group
        return result(effect, false, nil, "invalid ui.highlight.define group") unless group.matches?(/^[A-Za-z0-9._:-]{1,64}$/)
        return result(effect, false, nil, "invalid ui.highlight.define foreground") if foreground && !(0..255).includes?(foreground)
        return result(effect, false, nil, "capability approval denied") unless authorize("ui.highlight.define", group, "Define UI highlighting style")
        return result(effect, false, nil, "UI sink is unavailable") unless sink = ui_sink

        style_id = sink.define_ui_style(group, foreground, bold, underline, owner)
        result(effect, true, {"group" => style_id})
      rescue ex
        result(effect, false, nil, ex.message || ex.class.name)
      end

      private def handle_panel_open(effect : PanelOpenEffect) : Result
        type = effect.type
        id = effect.id
        buffer_id = effect.buffer_id
        title = effect.title
        position = effect.position
        focus = effect.focus
        owner = ui_owner
        return result(effect, false, nil, "ui.panel.open requires an extension owner") unless owner
        return result(effect, false, nil, "ui.panel.open requires id and buffer_id") unless id && buffer_id
        return result(effect, false, nil, "ui.panel.open requires a title") unless title
        return result(effect, false, nil, "invalid ui.panel.open id") unless id.matches?(/^[A-Za-z0-9._:-]{1,128}$/)
        return result(effect, false, nil, "invalid ui.panel.open buffer_id") unless buffer_id.matches?(/^[A-Za-z0-9._:-]{1,128}$/)
        return result(effect, false, nil, "invalid ui.panel.open position") unless {"main", "right", "bottom"}.includes?(position)
        return result(effect, false, nil, "ui.panel.open title is too long") if title.bytesize > 256
        return result(effect, false, nil, "capability approval denied") unless authorize("ui.panel.open", id, "Open a UI panel")
        return result(effect, false, nil, "UI sink is unavailable") unless sink = ui_sink

        panel_id = sink.open_ui_panel(id, buffer_id, title, position, focus, owner)
        result(effect, true, {"panel_id" => panel_id})
      rescue ex
        result(effect, false, nil, ex.message || ex.class.name)
      end

      private def handle_panel_focus(effect : PanelFocusEffect) : Result
        type = effect.type
        id = effect.id
        owner = ui_owner
        return result(effect, false, nil, "ui.panel.focus requires an extension owner") unless owner
        return result(effect, false, nil, "ui.panel.focus requires an id") unless id
        return result(effect, false, nil, "invalid ui.panel.focus id") unless id.matches?(/^[A-Za-z0-9._:-]{1,128}$/)
        return result(effect, false, nil, "capability approval denied") unless authorize("ui.panel.focus", id, "Focus a UI panel")
        return result(effect, false, nil, "UI sink is unavailable") unless sink = ui_sink

        panel_id = sink.focus_ui_panel(id, owner)
        result(effect, true, {"panel_id" => panel_id})
      rescue ex
        result(effect, false, nil, ex.message || ex.class.name)
      end

      private def handle_http(effect : HttpRequestEffect) : Result
        type = effect.type
        url = effect.url
        return result(effect, false, nil, "network permission denied for #{url}") unless grants.allows_network?(url, requested)

        method = effect.method.upcase
        headers = HTTP::Headers.new
        effect.headers.each { |key, value| headers[key] = value }

        if auth = effect.auth
          secret = auth.secret
          return result(effect, false, nil, "secret permission denied for #{secret}") unless grants.allows_secret?(secret, requested)
          token = ENV[secret]?
          return result(effect, false, nil, "secret is not available: #{secret}") unless token
          scheme = auth.scheme
          headers["Authorization"] = scheme == "bearer" ? "Bearer #{token}" : token
        end

        body = effect.body.try(&.raw)
        if body && body.bytesize > MAX_HTTP_REQUEST_BYTES
          return result(effect, false, nil, "HTTP request body exceeds #{MAX_HTTP_REQUEST_BYTES} bytes")
        end
        return result(effect, false, nil, "capability approval denied") unless authorize("network.request", url, "Make an HTTP request")

        uri = URI.parse(url)
        client : HTTP::Client? = nil
        client = HTTP::Client.new(uri)
        client.connect_timeout = @http_connect_timeout
        client.read_timeout = @http_read_timeout
        request = HTTP::Request.new(method, uri.request_target, headers, body: body)
        result : Result? = nil

        client.not_nil!.exec(request) do |response|
          if response.status_code >= 300 && response.status_code < 400
            result = result(effect, false, nil, "HTTP redirects are not followed")
            next
          end

          if content_length = response.headers["Content-Length"]?.try(&.to_i64?)
            raise "HTTP response exceeds #{@max_http_response_bytes} bytes" if content_length > @max_http_response_bytes
          end

          payload = {
            "status"  => response.status_code,
            "headers" => response.headers.to_h,
            "body"    => read_response_body(response.body_io),
          }
          result = result(effect, true, payload)
        end
        result.not_nil!
      rescue ex
        result(effect, false, nil, ex.message || ex.class.name)
      ensure
        client.try(&.close)
      end

      private def read_response_body(io : IO) : String
        bytes = IO::Memory.new
        buffer = Bytes.new(8192)
        total = 0_i64
        loop do
          count = io.read(buffer)
          break if count == 0
          total += count
          raise "HTTP response exceeds #{@max_http_response_bytes} bytes" if total > @max_http_response_bytes
          bytes.write(buffer[0, count])
        end
        bytes.to_s
      end

      private def authorize(capability : String, target : String, reason : String) : Bool
        request_id = "cap-#{Random::Secure.hex(12)}"
        request = API::CapabilityRequest.new(request_id, actor, capability, target, reason)
        capabilities.authorize(request)
      end

      private def handle_file_read(effect : FileReadEffect) : Result
        path = effect.path
        resolved = PathSecurity.resolve_existing(path)
        return result(effect, false, nil, "file read permission denied for #{path}") unless resolved && grants.allows_file_read?(resolved, requested)
        return result(effect, false, nil, "capability approval denied") unless authorize("filesystem.read", resolved, "Read a file")
        result(effect, true, {"path" => resolved, "content" => File.read(resolved)})
      end

      private def handle_session_state_get(effect : SessionStateGetEffect) : Result
        owner = extension_owner
        return result(effect, false, nil, "session.state.get requires an extension owner") unless owner
        return result(effect, false, nil, "session state permission denied") unless grants.allows_session_state?(requested)
        current = session
        return result(effect, false, nil, "session.state.get requires an active session") unless current
        return result(effect, false, nil, "capability approval denied") unless authorize("session.state.read", current.id, "Read this extension's state for the active session")

        Result.new(effect.type, true, current.extension_data(owner))
      end

      private def handle_session_state_set(effect : SessionStateSetEffect) : Result
        owner = extension_owner
        return result(effect, false, nil, "session.state.set requires an extension owner") unless owner
        return result(effect, false, nil, "session state permission denied") unless grants.allows_session_state?(requested)
        current = session
        return result(effect, false, nil, "session.state.set requires an active session") unless current
        return result(effect, false, nil, "session extension state exceeds #{MAX_SESSION_STATE_BYTES} bytes") if effect.value.bytesize > MAX_SESSION_STATE_BYTES
        return result(effect, false, nil, "capability approval denied") unless authorize("session.state.write", current.id, "Update this extension's state for the active session")

        current.set_extension_data(owner, effect.value)
        events.emit(Event.new("session.extension_state.updated", JSON.parse({
          "session_id"   => current.id,
          "extension_id" => owner,
        }.to_json), owner))
        result(effect, true, {"updated" => true})
      end

      private def extension_owner : String?
        return nil if actor == "host"
        actor
      end

      private def handle_filesystem_list(effect : FilesystemListEffect) : Result
        type = effect.type
        path = effect.path
        resolved = PathSecurity.resolve_existing(path, workspace_root)
        return result(effect, false, nil, "directory is outside workspace or does not exist: #{path}") unless resolved
        return result(effect, false, nil, "directory is outside workspace: #{path}") unless PathSecurity.within?(resolved, workspace_root)
        return result(effect, false, nil, "filesystem.list requires a directory") unless Dir.exists?(resolved)
        return result(effect, false, nil, "file read permission denied for #{path}") unless grants.allows_file_read?(resolved, requested, workspace_root)
        return result(effect, false, nil, "capability approval denied") unless authorize("filesystem.list", resolved, "List directory contents")

        entries = Dir.children(resolved).sort.map do |name|
          entry_path = File.join(resolved, name)
          kind = Dir.exists?(entry_path) ? "directory" : "file"
          {"name" => name, "type" => kind}
        end
        result(effect, true, {"path" => resolved, "entries" => entries})
      rescue ex
        result(effect, false, nil, ex.message || ex.class.name)
      end
    end
  end
end
