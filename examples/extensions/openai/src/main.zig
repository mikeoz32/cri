const cri = @import("cri_sdk");

const provider_effect = "[{\"type\":\"host.provider.register\",\"id\":\"openai\",\"title\":\"OpenAI\",\"api_type\":\"openai\",\"endpoint\":\"https://api.openai.com/v1/chat/completions\",\"model\":\"gpt-4o-mini\",\"auth_flows\":[{\"id\":\"api-key\",\"kind\":\"api_token\",\"metadata\":{\"env\":\"OPENAI_API_KEY\",\"validate\":\"api_client\"}},{\"id\":\"chatgpt\",\"kind\":\"oauth_browser\",\"metadata\":{\"api_type\":\"openai-codex-responses\",\"endpoint\":\"https://chatgpt.com/backend-api/codex/responses\",\"transport\":\"http+sse\",\"model\":\"gpt-5\"},\"oauth\":{\"authorization_endpoint\":\"https://auth.openai.com/oauth/authorize\",\"token_endpoint\":\"https://auth.openai.com/oauth/token\",\"client_id\":\"app_EMoamEEZ73f0CkXaXp7hrann\",\"scopes\":[\"openid\",\"profile\",\"email\",\"offline_access\"],\"redirect_uri\":\"http://localhost:1455/auth/callback\",\"extra_parameters\":{\"id_token_add_organizations\":\"true\",\"codex_cli_simplified_flow\":\"true\",\"originator\":\"codex_cli_rs\"}}}]}]";

fn call(_: cri.Request) cri.Response {
    return cri.Response.with_effects("null", provider_effect);
}

fn resume_extension(_: cri.Request) cri.Response {
    return cri.Response.success("null");
}

export fn cri_init() void {
    cri.register(.{ .call = call, .resume_fn = resume_extension });
}
