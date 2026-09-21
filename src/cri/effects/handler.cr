module Cri
  module Effects
    class Handler
      DEFAULT_HTTP_CONNECT_TIMEOUT = 10.seconds
      DEFAULT_HTTP_READ_TIMEOUT    = 30.seconds
      DEFAULT_HTTP_RESPONSE_BYTES  = 4_i64 * 1024_i64 * 1024_i64
      MAX_HTTP_REQUEST_BYTES       = 1_i64 * 1024_i64 * 1024_i64

      getter grants : Permissions::GrantSet
      getter requested : Permissions::Request
      getter ui_sink : UiSink?
      getter ui_owner : String?
      getter capabilities : API::CapabilityBroker
      getter actor : String

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
      )
      end

      def handle(effect : JSON::Any) : Result
        type = effect["type"].as_s
        case type
        when "http.request"
          handle_http(type, effect)
        when "file.read"
          handle_file_read(type, effect)
        when "file.propose_edit"
          Result.new(type, true, JSON.parse({"accepted" => false, "message" => "edit proposal recorded; apply flow not implemented yet"}.to_json))
        when "ui.notification"
          handle_notification(type, effect)
        when "ui.buffer.create"
          handle_buffer_create(type, effect)
        when "ui.buffer.append"
          handle_buffer_mutation(type, effect, "append")
        when "ui.buffer.replace"
          handle_buffer_mutation(type, effect, "replace")
        when "ui.highlight.set"
          handle_highlight_set(type, effect)
        when "ui.highlight.define"
          handle_highlight_define(type, effect)
        when "ui.panel.open"
          handle_panel_open(type, effect)
        when "ui.panel.focus"
          handle_panel_focus(type, effect)
        when "ui.status_update"
          Result.new(type, true, JSON.parse({"updated" => true}.to_json))
        else
          Result.new(type, false, nil, "unsupported effect type")
        end
      rescue ex
        Result.new("unknown", false, nil, ex.message || ex.class.name)
      end

      private def handle_notification(type : String, effect : JSON::Any) : Result
        message = effect["message"]?.try(&.as_s?)
        level = effect["level"]?.try(&.as_s?) || "info"
        return Result.new(type, false, nil, "ui.notification requires a message") unless message
        return Result.new(type, false, nil, "invalid ui.notification level") unless {"info", "success", "warning", "error"}.includes?(level)
        return Result.new(type, false, nil, "ui.notification message is too long") if message.bytesize > 16_i64 * 1024_i64

        return Result.new(type, false, nil, "capability approval denied") unless authorize("ui.notification", level, "Show a notification")
        ui_sink.try(&.notify(message, level))
        Result.new(type, true, JSON.parse({"shown" => true, "level" => level}.to_json))
      end

      private def handle_buffer_create(type : String, effect : JSON::Any) : Result
        id = effect["id"]?.try(&.as_s?)
        content = effect["content"]?.try(&.as_s?) || ""
        owner = ui_owner
        return Result.new(type, false, nil, "ui.buffer.create requires an extension owner") unless owner
        return Result.new(type, false, nil, "ui.buffer.create requires an id") unless id
        return Result.new(type, false, nil, "invalid ui.buffer.create id") unless id.matches?(/^[A-Za-z0-9._:-]{1,128}$/)
        return Result.new(type, false, nil, "ui.buffer.create content is too long") if content.bytesize > 4_i64 * 1024_i64 * 1024_i64
        return Result.new(type, false, nil, "capability approval denied") unless authorize("ui.buffer.create", id, "Create a UI buffer")
        return Result.new(type, false, nil, "UI sink is unavailable") unless sink = ui_sink

        buffer_id = sink.create_ui_buffer(id, content, owner)
        Result.new(type, true, JSON.parse({"buffer_id" => buffer_id, "owner" => owner}.to_json))
      rescue ex
        Result.new(type, false, nil, ex.message || ex.class.name)
      end

      private def handle_buffer_mutation(type : String, effect : JSON::Any, operation : String) : Result
        id = effect["id"]?.try(&.as_s?)
        content = effect["content"]?.try(&.as_s?)
        owner = ui_owner
        return Result.new(type, false, nil, "#{type} requires an extension owner") unless owner
        return Result.new(type, false, nil, "#{type} requires an id") unless id
        return Result.new(type, false, nil, "#{type} requires content") unless content
        return Result.new(type, false, nil, "invalid #{type} id") unless id.matches?(/^[A-Za-z0-9._:-]{1,128}$/)
        return Result.new(type, false, nil, "#{type} content is too long") if content.bytesize > 4_i64 * 1024_i64 * 1024_i64
        return Result.new(type, false, nil, "capability approval denied") unless authorize("ui.buffer.#{operation}", id, "Modify a UI buffer")
        return Result.new(type, false, nil, "UI sink is unavailable") unless sink = ui_sink

        buffer_id = operation == "append" ? sink.append_ui_buffer(id, content, owner) : sink.replace_ui_buffer(id, content, owner)
        Result.new(type, true, JSON.parse({"buffer_id" => buffer_id}.to_json))
      rescue ex
        Result.new(type, false, nil, ex.message || ex.class.name)
      end

      private def handle_highlight_set(type : String, effect : JSON::Any) : Result
        id = effect["id"]?.try(&.as_s?)
        group = effect["group"]?.try(&.as_s?)
        start = effect["start"]?.try(&.as_i?)
        finish = effect["finish"]?.try(&.as_i?)
        owner = ui_owner
        return Result.new(type, false, nil, "ui.highlight.set requires an extension owner") unless owner
        return Result.new(type, false, nil, "ui.highlight.set requires an id") unless id
        return Result.new(type, false, nil, "ui.highlight.set requires a group") unless group
        return Result.new(type, false, nil, "ui.highlight.set requires start and finish") unless start && finish
        return Result.new(type, false, nil, "invalid ui.highlight.set id") unless id.matches?(/^[A-Za-z0-9._:-]{1,128}$/)
        return Result.new(type, false, nil, "invalid ui.highlight.set group") unless group.matches?(/^[A-Za-z0-9._:-]{1,64}$/)
        return Result.new(type, false, nil, "invalid ui.highlight.set range") unless start >= 0 && finish > start
        return Result.new(type, false, nil, "capability approval denied") unless authorize("ui.highlight.set", id, "Set UI highlighting")
        return Result.new(type, false, nil, "UI sink is unavailable") unless sink = ui_sink

        buffer_id = sink.set_ui_highlight(id, start, finish, group, owner)
        Result.new(type, true, JSON.parse({"buffer_id" => buffer_id}.to_json))
      rescue ex
        Result.new(type, false, nil, ex.message || ex.class.name)
      end

      private def handle_highlight_define(type : String, effect : JSON::Any) : Result
        group = effect["group"]?.try(&.as_s?)
        foreground = effect["foreground"]?.try(&.as_i?)
        bold = effect["bold"]?.try(&.as_bool?) || false
        underline = effect["underline"]?.try(&.as_bool?) || false
        owner = ui_owner
        return Result.new(type, false, nil, "ui.highlight.define requires an extension owner") unless owner
        return Result.new(type, false, nil, "ui.highlight.define requires a group") unless group
        return Result.new(type, false, nil, "invalid ui.highlight.define group") unless group.matches?(/^[A-Za-z0-9._:-]{1,64}$/)
        return Result.new(type, false, nil, "invalid ui.highlight.define foreground") if foreground && !(0..255).includes?(foreground)
        return Result.new(type, false, nil, "capability approval denied") unless authorize("ui.highlight.define", group, "Define UI highlighting style")
        return Result.new(type, false, nil, "UI sink is unavailable") unless sink = ui_sink

        style_id = sink.define_ui_style(group, foreground, bold, underline, owner)
        Result.new(type, true, JSON.parse({"group" => style_id}.to_json))
      rescue ex
        Result.new(type, false, nil, ex.message || ex.class.name)
      end

      private def handle_panel_open(type : String, effect : JSON::Any) : Result
        id = effect["id"]?.try(&.as_s?)
        buffer_id = effect["buffer_id"]?.try(&.as_s?)
        title = effect["title"]?.try(&.as_s?)
        position = effect["position"]?.try(&.as_s?) || "right"
        focus = effect["focus"]?.try(&.as_bool?) || false
        owner = ui_owner
        return Result.new(type, false, nil, "ui.panel.open requires an extension owner") unless owner
        return Result.new(type, false, nil, "ui.panel.open requires id and buffer_id") unless id && buffer_id
        return Result.new(type, false, nil, "ui.panel.open requires a title") unless title
        return Result.new(type, false, nil, "invalid ui.panel.open id") unless id.matches?(/^[A-Za-z0-9._:-]{1,128}$/)
        return Result.new(type, false, nil, "invalid ui.panel.open buffer_id") unless buffer_id.matches?(/^[A-Za-z0-9._:-]{1,128}$/)
        return Result.new(type, false, nil, "invalid ui.panel.open position") unless {"main", "right", "bottom"}.includes?(position)
        return Result.new(type, false, nil, "ui.panel.open title is too long") if title.bytesize > 256
        return Result.new(type, false, nil, "capability approval denied") unless authorize("ui.panel.open", id, "Open a UI panel")
        return Result.new(type, false, nil, "UI sink is unavailable") unless sink = ui_sink

        panel_id = sink.open_ui_panel(id, buffer_id, title, position, focus, owner)
        Result.new(type, true, JSON.parse({"panel_id" => panel_id}.to_json))
      rescue ex
        Result.new(type, false, nil, ex.message || ex.class.name)
      end

      private def handle_panel_focus(type : String, effect : JSON::Any) : Result
        id = effect["id"]?.try(&.as_s?)
        owner = ui_owner
        return Result.new(type, false, nil, "ui.panel.focus requires an extension owner") unless owner
        return Result.new(type, false, nil, "ui.panel.focus requires an id") unless id
        return Result.new(type, false, nil, "invalid ui.panel.focus id") unless id.matches?(/^[A-Za-z0-9._:-]{1,128}$/)
        return Result.new(type, false, nil, "capability approval denied") unless authorize("ui.panel.focus", id, "Focus a UI panel")
        return Result.new(type, false, nil, "UI sink is unavailable") unless sink = ui_sink

        panel_id = sink.focus_ui_panel(id, owner)
        Result.new(type, true, JSON.parse({"panel_id" => panel_id}.to_json))
      rescue ex
        Result.new(type, false, nil, ex.message || ex.class.name)
      end

      private def handle_http(type : String, effect : JSON::Any) : Result
        url = effect["url"].as_s
        return Result.new(type, false, nil, "network permission denied for #{url}") unless grants.allows_network?(url, requested)

        method = effect["method"]?.try(&.as_s.upcase) || "GET"
        headers = HTTP::Headers.new
        if h = effect["headers"]?
          h.as_h.each { |k, v| headers[k] = v.as_s }
        end

        if auth = effect["auth"]?
          secret = auth["secret"].as_s
          return Result.new(type, false, nil, "secret permission denied for #{secret}") unless grants.allows_secret?(secret, requested)
          token = ENV[secret]?
          return Result.new(type, false, nil, "secret is not available: #{secret}") unless token
          scheme = auth["as"]?.try(&.as_s) || "bearer"
          headers["Authorization"] = scheme == "bearer" ? "Bearer #{token}" : token
        end

        body = effect["body"]?.try(&.to_json)
        if body && body.bytesize > MAX_HTTP_REQUEST_BYTES
          return Result.new(type, false, nil, "HTTP request body exceeds #{MAX_HTTP_REQUEST_BYTES} bytes")
        end
        return Result.new(type, false, nil, "capability approval denied") unless authorize("network.request", url, "Make an HTTP request")

        uri = URI.parse(url)
        client : HTTP::Client? = nil
        client = HTTP::Client.new(uri)
        client.connect_timeout = @http_connect_timeout
        client.read_timeout = @http_read_timeout
        request = HTTP::Request.new(method, uri.request_target, headers, body: body)
        result : Result? = nil

        client.not_nil!.exec(request) do |response|
          if response.status_code >= 300 && response.status_code < 400
            result = Result.new(type, false, nil, "HTTP redirects are not followed")
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
          result = Result.new(type, true, JSON.parse(payload.to_json))
        end
        result.not_nil!
      rescue ex
        Result.new(type, false, nil, ex.message || ex.class.name)
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

      private def handle_file_read(type : String, effect : JSON::Any) : Result
        path = effect["path"].as_s
        resolved = PathSecurity.resolve_existing(path)
        return Result.new(type, false, nil, "file read permission denied for #{path}") unless resolved && grants.allows_file_read?(resolved, requested)
        return Result.new(type, false, nil, "capability approval denied") unless authorize("filesystem.read", resolved, "Read a file")
        Result.new(type, true, JSON.parse({"path" => resolved, "content" => File.read(resolved)}.to_json))
      end
    end
  end
end
