require "random/secure"

module Cri
  module Auth
    enum FlowKind
      ApiToken
      OAuthDevice
      OAuthBrowser
    end

    class Flow
      getter id : String
      getter kind : FlowKind
      getter metadata : Hash(String, String)

      def initialize(@id : String, @kind : FlowKind, @metadata : Hash(String, String) = {} of String => String)
      end
    end

    class Provider
      getter id : String
      getter title : String
      getter flows : Array(Flow)

      def initialize(@id : String, @title : String, @flows : Array(Flow))
      end

      def flow(id : String) : Flow
        flows.find { |item| item.id == id } || raise "unknown auth flow: #{id}"
      end
    end

    class CredentialRef
      getter id : String
      getter provider_id : String
      getter flow_id : String

      def initialize(@id : String, @provider_id : String, @flow_id : String)
      end

      def to_json(json : JSON::Builder)
        json.object do
          json.field "id", id
          json.field "provider", provider_id
          json.field "flow", flow_id
        end
      end
    end

    class Credential
      getter ref : CredentialRef
      getter secret : String

      def initialize(@ref : CredentialRef, @secret : String)
      end
    end

    abstract class CredentialStore
      def self.default : CredentialStore
        if SecretServiceCredentialStore.available?
          SecretServiceCredentialStore.new
        else
          MemoryCredentialStore.new
        end
      end

      abstract def save(credential : Credential)
      abstract def get(ref : CredentialRef) : Credential?
      abstract def delete(ref : CredentialRef)

      def persistent? : Bool
        false
      end
    end

    class MemoryCredentialStore < CredentialStore
      @credentials = {} of String => Credential

      def save(credential : Credential)
        @credentials[credential.ref.id] = credential
      end

      def get(ref : CredentialRef) : Credential?
        @credentials[ref.id]?
      end

      def delete(ref : CredentialRef)
        @credentials.delete(ref.id)
      end
    end

    # Linux Secret Service adapter. secret-tool receives the secret on stdin,
    # never in process arguments, so it cannot appear in the process list.
    class SecretServiceCredentialStore < CredentialStore
      def self.available? : Bool
        !!Process.find_executable("secret-tool") && !ENV["DBUS_SESSION_BUS_ADDRESS"]?.try(&.empty?)
      end

      def save(credential : Credential)
        run("store", "--label=cri credential", "provider", credential.ref.provider_id, "flow", credential.ref.flow_id, "id", credential.ref.id, input: credential.secret)
        raise "secret service failed to store credential" unless @last_status
      end

      def get(ref : CredentialRef) : Credential?
        output = run("lookup", "provider", ref.provider_id, "flow", ref.flow_id, "id", ref.id)
        return nil unless @last_status
        secret = output.rstrip
        return nil if secret.empty?
        Credential.new(ref, secret)
      end

      def delete(ref : CredentialRef)
        run("clear", "provider", ref.provider_id, "flow", ref.flow_id, "id", ref.id)
      end

      def persistent? : Bool
        true
      end

      private getter last_status : Bool = false

      private def run(*args : String, input : String? = nil) : String
        output = IO::Memory.new
        input_io = input ? IO::Memory.new(input.not_nil!) : Process::Redirect::Inherit
        status = Process.run("secret-tool", args: args.to_a, input: input_io, output: output, error: Process::Redirect::Inherit)
        @last_status = status.success?
        output.to_s
      end
    end

    # Host-only authentication broker. Extensions receive CredentialRef values
    # at most; the secret remains inside the host and its provider adapter.
    class Broker
      getter store : CredentialStore
      @providers = {} of String => Provider

      def initialize(@store : CredentialStore = CredentialStore.default)
      end

      def register(provider : Provider)
        raise "auth provider already registered: #{provider.id}" if @providers.has_key?(provider.id)
        @providers[provider.id] = provider
      end

      def provider(id : String) : Provider
        @providers[id]? || raise "unknown auth provider: #{id}"
      end

      def providers : Array(Provider)
        @providers.values
      end

      def import_api_token(provider_id : String, flow_id : String, token : String) : CredentialRef
        flow = provider(provider_id).flow(flow_id)
        raise "auth flow is not an API token flow" unless flow.kind.api_token?
        raise ArgumentError.new("credential token is empty") if token.empty?

        ref = CredentialRef.new("cred-#{Random::Secure.hex(16)}", provider_id, flow_id)
        store.save(Credential.new(ref, token))
        ref
      end

      def import_env(provider_id : String, flow_id : String, env_name : String) : CredentialRef?
        token = ENV[env_name]?
        return nil unless token && !token.empty?
        import_api_token(provider_id, flow_id, token)
      end

      # This is intentionally a host-side operation. Do not pass Broker or
      # Credential objects through extension/WASM input.
      def secret(ref : CredentialRef) : String
        store.get(ref).try(&.secret) || raise "credential is not available"
      end

      def remove(ref : CredentialRef)
        store.delete(ref)
      end
    end
  end
end
