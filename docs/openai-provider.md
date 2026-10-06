# OpenAI provider

The first-party `openai` API client uses OpenAI's Responses API and includes
the native `web_search` tool in requests. OpenAI decides when to search; cri
does not add a separate search extension or expose search results as a cri tool.
Responses containing URL citations include a Markdown `Sources` list.

The `openai-compatible` API client remains available for services that use the
Chat Completions wire format. ChatGPT OAuth uses the separate
`openai-codex-responses` API client.
