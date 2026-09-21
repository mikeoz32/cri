require "json"
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
      getter source : String

      def initialize(@id : String, @title : String, @flows : Array(Flow), @source : String = "built-in")
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
        FileCredentialStore.new
      end

      abstract def save(credential : Credential)
      abstract def get(ref : CredentialRef) : Credential?
      abstract def delete(ref : CredentialRef)

      def find(provider_id : String, flow_id : String) : CredentialRef?
        nil
      end

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

      def find(provider_id : String, flow_id : String) : CredentialRef?
        @credentials.values.find { |credential| credential.ref.provider_id == provider_id && credential.ref.flow_id == flow_id }.try(&.ref)
      end
    end

    class FileCredentialStore < CredentialStore
      VERSION = 1

      getter path : String

      def self.default_path : String
        home = ENV["HOME"]? || "."
        config_home = ENV["XDG_CONFIG_HOME"]? || File.join(home, ".config")
        File.join(config_home, "cri", "auth.json")
      end

      def initialize(@path : String = self.class.default_path)
        ensure_directory
      end

      def save(credential : Credential)
        with_lock do |records|
          records[credential.ref.id] = record_for(credential)
          write_records(records)
        end
      end

      def get(ref : CredentialRef) : Credential?
        with_lock(shared: true) do |records|
          record = records[ref.id]?
          record_to_credential(ref, record)
        end
      end

      def delete(ref : CredentialRef)
        with_lock do |records|
          records.delete(ref.id)
          write_records(records)
        end
      end

      def find(provider_id : String, flow_id : String) : CredentialRef?
        with_lock(shared: true) do |records|
          records.each do |id, record|
            next unless record["provider"]?.try(&.as_s?) == provider_id
            next unless record["flow"]?.try(&.as_s?) == flow_id
            return CredentialRef.new(id, provider_id, flow_id)
          end
          nil
        end
      end

      def persistent? : Bool
        true
      end

      private def ensure_directory
        directory = File.dirname(path)
        Dir.mkdir_p(directory)
        File.chmod(directory, 0o700)
        File.chmod(path, 0o600) if File.exists?(path)
      end

      private def lock_path : String
        "#{path}.lock"
      end

      private def with_lock(shared : Bool = false, & : Hash(String, JSON::Any) -> _)
        File.open(lock_path, "a+") do |lock|
          lock.chmod(0o600)
          shared ? lock.flock_shared : lock.flock_exclusive
          begin
            yield read_records
          ensure
            lock.flock_unlock
          end
        end
      end

      private def read_records : Hash(String, JSON::Any)
        return {} of String => JSON::Any unless File.exists?(path)
        root = JSON.parse(File.read(path)).as_h
        version = root["version"]?.try(&.as_i?)
        raise "unsupported cri auth store version" unless version == VERSION
        root["credentials"]?.try(&.as_h) || {} of String => JSON::Any
      end

      private def record_for(credential : Credential) : JSON::Any
        JSON.parse({
          "provider" => credential.ref.provider_id,
          "flow"     => credential.ref.flow_id,
          "secret"   => credential.secret,
        }.to_json)
      end

      private def record_to_credential(ref : CredentialRef, record : JSON::Any?) : Credential?
        return nil unless record
        hash = record.as_h
        secret = hash["secret"]?.try(&.as_s?)
        secret ? Credential.new(ref, secret) : nil
      end

      private def write_records(records : Hash(String, JSON::Any))
        temporary = "#{path}.tmp-#{Process.pid}-#{Random::Secure.hex(6)}"
        begin
          File.open(temporary, "w", perm: 0o600) do |file|
            file.print({"version" => VERSION, "credentials" => records}.to_json)
            file.flush
            file.fsync
          end
          File.rename(temporary, path)
          File.chmod(path, 0o600)
        ensure
          File.delete(temporary) if File.exists?(temporary)
        end
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
        return existing(provider_id, flow_id) unless token && !token.empty?
        import_api_token(provider_id, flow_id, token)
      end

      def existing(provider_id : String, flow_id : String) : CredentialRef?
        provider(provider_id).flow(flow_id)
        store.find(provider_id, flow_id)
      end

      # This is intentionally a host-side operation. Do not pass Broker or
      # Credential objects through extension/WASM input.
      def secret(ref : CredentialRef) : String
        store.get(ref).try(&.secret) || raise "credential is not available"
      end

      def remove(ref : CredentialRef)
        store.delete(ref)
      end

      def logout(provider_id : String, flow_id : String)
        store.find(provider_id, flow_id).try { |ref| store.delete(ref) }
      end
    end
  end
end
