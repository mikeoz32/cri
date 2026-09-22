require "base64"
require "digest/sha256"
require "http/client"
require "http/server"
require "json"
require "random/secure"
require "uri"

module Cri
  module Auth
    record OAuthTokens,
      access_token : String,
      refresh_token : String?,
      token_type : String,
      expires_in : Int64?,
      id_token : String? = nil,
      account_id : String? = nil do
      def to_json(json : JSON::Builder)
        json.object do
          json.field "access_token", access_token
          json.field "refresh_token", refresh_token if refresh_token
          json.field "token_type", token_type
          json.field "expires_in", expires_in if expires_in
          json.field "id_token", id_token if id_token
          json.field "account_id", account_id if account_id
        end
      end
    end

    class OAuthClient
      DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code"

      def initialize(@timeout : Time::Span = 60.seconds)
      end

      def device_login(config : OAuthConfig, &on_status : String ->) : OAuthTokens
        return openai_codex_device_login(config) { |status| on_status.call(status) } if config.device_protocol == "openai_codex"
        endpoint = config.device_authorization_endpoint || raise "OAuth flow has no device authorization endpoint"
        device = post_form(endpoint, {
          "client_id" => config.client_id,
          "scope"     => config.scopes.join(" "),
        }.merge(config.extra_parameters))
        device_code = device["device_code"]?.try(&.as_s) || raise "OAuth device response omitted device_code"
        user_code = device["user_code"]?.try(&.as_s) || raise "OAuth device response omitted user_code"
        verification_uri = device["verification_uri"]?.try(&.as_s) || device["verification_url"]?.try(&.as_s) || raise "OAuth device response omitted verification URI"
        expires_in = integer_value(device["expires_in"]?, 600_i64)
        interval = integer_value(device["interval"]?, 5_i64)
        on_status.call("Open #{verification_uri}")
        on_status.call("Code: #{user_code}")

        deadline = Time.utc + expires_in.seconds
        loop do
          raise "OAuth device authorization expired" if Time.utc >= deadline
          sleep interval.seconds
          response = post_form(endpoint: config.token_endpoint, form: {
            "grant_type"  => DEVICE_GRANT,
            "device_code" => device_code,
            "client_id"   => config.client_id,
          }.merge(config.extra_parameters), allow_error: true)
          if response["access_token"]?
            return tokens_from(response)
          end

          case response["error"]?.try(&.as_s?)
          when "authorization_pending"
            next
          when "slow_down"
            interval += 5
          when "access_denied"
            raise "OAuth authorization denied"
          when "expired_token"
            raise "OAuth device authorization expired"
          else
            raise "OAuth token request failed#{response["error_description"]?.try { |value| ": #{value.as_s}" } || ""}"
          end
        end
      end

      private def openai_codex_device_login(config : OAuthConfig, &on_status : String ->) : OAuthTokens
        endpoint = config.device_authorization_endpoint || raise "OAuth device flow has no user-code endpoint"
        device = post_json(endpoint, {"client_id" => config.client_id})
        device_id = device["device_auth_id"]?.try(&.as_s) || raise "device response omitted device_auth_id"
        user_code = device["user_code"]?.try(&.as_s) || raise "device response omitted user_code"
        interval = integer_value(device["interval"]?, 5_i64)
        verification = config.device_verification_uri || raise "device flow has no verification URI"
        on_status.call("Open #{verification}")
        on_status.call("Code: #{user_code}")

        deadline = Time.utc + 30.minutes
        loop do
          raise "OAuth device authorization expired" if Time.utc >= deadline
          sleep interval.seconds
          response = post_json(config.device_token_endpoint || raise("device flow has no token endpoint"), {"device_auth_id" => device_id, "user_code" => user_code}, allow_error: true)
          if authorization_code = response["authorization_code"]?.try(&.as_s?)
            verifier = response["code_verifier"]?.try(&.as_s) || raise "device response omitted code_verifier"
            redirect_uri = config.device_redirect_uri || raise "device flow has no redirect URI"
            token = post_form(config.token_endpoint, {
              "grant_type"    => "authorization_code",
              "client_id"     => config.client_id,
              "code"          => authorization_code,
              "code_verifier" => verifier,
              "redirect_uri"  => redirect_uri,
            }.merge(config.extra_parameters))
            return tokens_from(token)
          end
          next if response["error"]?.try(&.as_s?) == "authorization_pending"
          raise "OAuth device authorization failed" if response["error"]?
          # Codex returns 403/404 while the user has not completed login.
        end
      end

      def browser_login(config : OAuthConfig, &on_status : String ->) : OAuthTokens
        authorization_endpoint = config.authorization_endpoint || raise "OAuth flow has no authorization endpoint"
        verifier = Random::Secure.hex(32)
        challenge = Base64.urlsafe_encode(Digest::SHA256.digest(verifier)).gsub("=", "")
        state = Random::Secure.hex(24)
        result = Channel(Tuple(String?, String?, String?)).new(1)
        configured_redirect = config.redirect_uri
        callback_uri = configured_redirect.try { |value| URI.parse(value) }
        callback_path = callback_uri.try(&.path)
        server = HTTP::Server.new do |context|
          if context.request.path != (callback_path || "/callback")
            context.response.status_code = 404
            next
          end
          code = context.request.query_params["code"]?
          returned_state = context.request.query_params["state"]?
          error = context.request.query_params["error"]?
          if returned_state != state
            context.response.status_code = 400
            context.response.print("Invalid OAuth state")
            result.send({nil, nil, "invalid OAuth state"})
          else
            context.response.print("Authentication complete. You may close this window.")
            result.send({code, returned_state, error})
          end
        end
        callback_port = callback_uri.try(&.port) || 0
        address = server.bind_tcp("127.0.0.1", callback_port)
        redirect_uri = (configured_redirect || "http://127.0.0.1:{port}/callback").gsub("{port}", address.port.to_s)
        spawn { server.listen }

        params = {
          "response_type"         => "code",
          "client_id"             => config.client_id,
          "redirect_uri"          => redirect_uri,
          "scope"                 => config.scopes.join(" "),
          "state"                 => state,
          "code_challenge"        => challenge,
          "code_challenge_method" => "S256",
        }.merge(config.extra_parameters)
        url = "#{authorization_endpoint}#{authorization_endpoint.includes?("?") ? "&" : "?"}#{URI::Params.encode(params)}"
        on_status.call("Open #{url}")
        open_browser(url)

        code, _, error = result.receive
        raise "OAuth authorization failed: #{error}" if error
        raise "OAuth callback omitted authorization code" unless code
        begin
          response = post_form(config.token_endpoint, {
            "grant_type"    => "authorization_code",
            "code"          => code.not_nil!,
            "redirect_uri"  => redirect_uri,
            "client_id"     => config.client_id,
            "code_verifier" => verifier,
          }.merge(config.extra_parameters))
          tokens_from(response)
        ensure
          server.close
        end
      end

      def refresh(config : OAuthConfig, refresh_token : String) : OAuthTokens
        response = post_form(config.token_endpoint, {
          "grant_type"    => "refresh_token",
          "refresh_token" => refresh_token,
          "client_id"     => config.client_id,
        }.merge(config.extra_parameters))
        tokens_from(response, refresh_token)
      end

      private def tokens_from(response : Hash(String, JSON::Any), fallback_refresh : String? = nil) : OAuthTokens
        access = response["access_token"]?.try(&.as_s) || raise "OAuth token response omitted access_token"
        id_token = response["id_token"]?.try(&.as_s?)
        account_id = id_token.try { |token| account_id_from_jwt(token) }
        expires = integer_value(response["expires_in"]?, 0_i64)
        OAuthTokens.new(
          access,
          response["refresh_token"]?.try(&.as_s?) || fallback_refresh,
          response["token_type"]?.try(&.as_s) || "Bearer",
          expires == 0_i64 ? nil : expires,
          id_token,
          account_id
        )
      end

      private def integer_value(value : JSON::Any?, fallback : Int64) : Int64
        return fallback unless value
        case value.raw
        when String
          value.as_s.to_i64? || fallback
        when Int64
          value.as_i64
        else
          fallback
        end
      end

      private def account_id_from_jwt(token : String) : String?
        parts = token.split('.')
        return nil unless parts.size >= 2
        padding = (4 - parts[1].size % 4) % 4
        json = JSON.parse(Base64.decode_string(parts[1] + ("=" * padding)))
        json["https://api.openai.com/auth"]?.try(&.as_h).try { |claims| claims["chatgpt_account_id"]?.try(&.as_s?) } ||
          json["chatgpt_account_id"]?.try(&.as_s?)
      rescue
        nil
      end

      private def open_browser(url : String)
        return if ENV["CRI_NO_BROWSER"]? == "1"
        Process.run("xdg-open", args: [url], output: Process::Redirect::Close, error: Process::Redirect::Close)
      rescue
        # The URL was already reported to the client.
      end

      private def post_json(endpoint : String, payload : Hash(String, String), allow_error : Bool = false) : Hash(String, JSON::Any)
        uri = URI.parse(endpoint)
        client = HTTP::Client.new(uri)
        client.connect_timeout = @timeout
        client.read_timeout = @timeout
        response = client.post(uri.request_target, headers: HTTP::Headers{"Content-Type" => "application/json"}, body: payload.to_json)
        body = response.body.empty? ? {} of String => JSON::Any : JSON.parse(response.body).as_h
        unless response.success?
          return JSON.parse(%({"error":"authorization_pending"})).as_h if allow_error && {403, 404}.includes?(response.status_code)
          raise "OAuth HTTP error (#{response.status_code})"
        end
        body
      ensure
        client.try(&.close)
      end

      private def post_form(endpoint : String, form : Hash(String, String), allow_error : Bool = false) : Hash(String, JSON::Any)
        uri = URI.parse(endpoint)
        client = HTTP::Client.new(uri)
        client.connect_timeout = @timeout
        client.read_timeout = @timeout
        response = client.post(uri.request_target, headers: HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, body: URI::Params.encode(form))
        body = JSON.parse(response.body).as_h
        raise "OAuth HTTP error (#{response.status_code})" unless response.success? || allow_error
        body
      ensure
        client.try(&.close)
      end
    end
  end
end
