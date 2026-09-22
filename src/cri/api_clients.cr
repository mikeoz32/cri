module Cri
  class APIClientRegistry
    alias Factory = Proc(ProviderRegistration, String?, APIClient)

    getter types : Hash(String, Factory)

    def initialize
      @types = {} of String => Factory
    end

    def register(api_type : String, &factory : ProviderRegistration, String? -> APIClient)
      raise "duplicate API client type: #{api_type}" if types.has_key?(api_type)
      types[api_type] = factory
    end

    def build(registration : ProviderRegistration, secret : String?) : APIClient
      factory = types[registration.api_type]? || raise "no API client registered for api type: #{registration.api_type}"
      factory.call(registration, secret)
    end

    def validate(registration : ProviderRegistration, secret : String) : Nil
      build(registration, secret).validate_credentials
    end
  end
end
