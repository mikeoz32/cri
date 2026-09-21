require "json"

module Cri
  module Auth
    record CodexLoginResult, login_id : String, auth_url : String, home : String

    # Thin host-owned adapter for the documented Codex app-server protocol.
    # It deliberately does not implement OAuth, PKCE, token exchange, or
    # scrape ChatGPT. The app-server owns that protocol and its auth state.
    class CodexAppServer
      getter home : String

      def initialize(@home : String = self.class.default_home, @executable : String? = nil)
        ensure_home
      end

      def self.default_home : String
        config_home = ENV["XDG_CONFIG_HOME"]? || File.join(ENV["HOME"]? || ".", ".config")
        File.join(config_home, "cri", "codex")
      end

      def login_browser(&on_status : String ->) : CodexLoginResult
        candidate = @executable || ENV["CRI_CODEX_BIN"]?
        executable = if candidate
                       Process.find_executable(candidate) || (File.exists?(candidate) ? candidate : nil)
                     else
                       Process.find_executable("codex")
                     end
        raise "Codex executable not found; install Codex or set CRI_CODEX_BIN" unless executable

        process = Process.new(
          executable.not_nil!,
          ["app-server"],
          env: {"CODEX_HOME" => home},
          input: Process::Redirect::Pipe,
          output: Process::Redirect::Pipe,
          error: Process::Redirect::Close
        )

        begin
          send_message(process, {
            "method" => "initialize",
            "id"     => 0,
            "params" => {
              "clientInfo" => {
                "name"    => "cri",
                "title"   => "cri",
                "version" => Cri::VERSION,
              },
            },
          })
          expect_response(process, 0)
          send_message(process, {"method" => "initialized", "params" => ({} of String => String)})

          send_message(process, {
            "method" => "account/login/start",
            "id"     => 1,
            "params" => {
              "type"                      => "chatgpt",
              "useHostedLoginSuccessPage" => true,
              "appBrand"                  => "chatgpt",
            },
          })

          start = expect_response(process, 1)
          result = start["result"]?.try(&.as_h) || raise_protocol_error(start)
          login_id = result["loginId"]?.try(&.as_s) || raise "Codex login response omitted loginId"
          auth_url = result["authUrl"]?.try(&.as_s) || raise "Codex login response omitted authUrl"
          on_status.call("open #{auth_url}")
          open_browser(auth_url)
          on_status.call("waiting for ChatGPT login")

          loop do
            message = read_message(process)
            if message["method"]?.try(&.as_s?) == "account/login/completed"
              params = message["params"]?.try(&.as_h) || {} of String => JSON::Any
              next unless params["loginId"]?.try(&.as_s?) == login_id
              success = params["success"]?.try(&.as_bool?) == true
              error = params["error"]?.try(&.as_s?)
              raise "Codex login failed#{error ? ": #{error}" : ""}" unless success
              on_status.call("ChatGPT login completed")
              break
            end
          end

          CodexLoginResult.new(login_id, auth_url, home)
        ensure
          process.terminate unless process.terminated?
          process.wait
          process.close
        end
      end

      private def ensure_home
        Dir.mkdir_p(home)
        File.chmod(home, 0o700)
      end

      private def send_message(process : Process, message : Hash(String, _))
        process.input.puts(message.to_json)
        process.input.flush
      end

      private def expect_response(process : Process, id : Int32) : Hash(String, JSON::Any)
        loop do
          message = read_message(process)
          next unless message["id"]?.try(&.as_i?) == id
          raise_protocol_error(message) if message["error"]?
          return message
        end
      end

      private def read_message(process : Process) : Hash(String, JSON::Any)
        line = process.output.gets
        raise "Codex app-server exited before completing authentication" unless line
        JSON.parse(line).as_h
      rescue ex : JSON::ParseException
        raise "Codex app-server returned invalid protocol data"
      end

      private def raise_protocol_error(message : Hash(String, JSON::Any)) : NoReturn
        error = message["error"]?.try(&.as_h)
        detail = error && error["message"]?.try(&.as_s?)
        raise "Codex app-server error#{detail ? ": #{detail}" : ""}"
      end

      private def open_browser(url : String)
        return if ENV["CRI_NO_BROWSER"]? == "1"
        Process.run("xdg-open", args: [url], output: Process::Redirect::Close, error: Process::Redirect::Close)
      rescue
        # The URL is already surfaced to the caller; a missing desktop opener
        # must not prevent manual browser login.
      end
    end
  end
end
