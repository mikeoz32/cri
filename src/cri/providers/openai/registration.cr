module Cri
  module Providers
    class OpenAI
      module Registration
        CLIENT_ID     = "app_EMoamEEZ73f0CkXaXp7hrann"
        AUTH_BASE_URL = "https://auth.openai.com"
        SCOPE         = "openid profile email offline_access"

        def self.register(registry : ProviderRegistry)
          oauth = Auth::OAuthConfig.new(
            "#{AUTH_BASE_URL}/oauth/token",
            CLIENT_ID,
            "#{AUTH_BASE_URL}/oauth/authorize",
            nil,
            SCOPE.split,
            "http://localhost:1455/auth/callback",
            nil,
            {
              "id_token_add_organizations" => "true",
              "codex_cli_simplified_flow"  => "true",
              "originator"                 => "cri",
            }
          )

          registry.register(ProviderRegistration.new(
            "openai",
            "OpenAI",
            "openai",
            [
              Auth::Flow.new("api-key", Auth::FlowKind::ApiToken, {"validator" => "openai-models"}),
              Auth::Flow.new("chatgpt", Auth::FlowKind::OAuthBrowser, {} of String => String, oauth),
            ],
            "extension:openai"
          ))
        end
      end
    end
  end
end
