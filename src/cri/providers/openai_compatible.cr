module Cri
  module Providers
    # Backwards-compatible name for the first provider implementation.
    # Convenience API-client specialization; it is not a provider registration
    # and does not own transport or credentials.
    class OpenAICompatible < OpenAI
    end
  end
end
