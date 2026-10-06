module Cri
  module Extensions
    class ContextBlockInput
      include JSON::Serializable

      property id : String
      property content : String

      def initialize(@id : String, @content : String)
      end
    end

    class ContextBlock
      include JSON::Serializable

      getter id : String
      getter source : String
      getter content : String

      def initialize(@id : String, @source : String, @content : String)
      end
    end

    class ContextPatch
      include JSON::Serializable

      property add : Array(ContextBlockInput) = [] of ContextBlockInput
      property remove : Array(String) = [] of String

      def initialize(@add : Array(ContextBlockInput) = [] of ContextBlockInput, @remove : Array(String) = [] of String)
      end
    end

    class ContextRequest
      include JSON::Serializable

      getter session_id : String
      getter messages : Array(Message)
      getter tools : Array(ToolSpec)
      getter blocks : Array(ContextBlock)

      def initialize(@session_id : String, @messages : Array(Message), @tools : Array(ToolSpec), @blocks : Array(ContextBlock))
      end
    end

    # Runs extension context providers in manifest order. Providers can add
    # blocks or remove a previously added block by its host-qualified ID.
    class ContextPipeline
      MAX_CONTEXT_BLOCKS        = 128
      MAX_CONTEXT_BLOCK_BYTES   = 32_i64 * 1024_i64
      MAX_CONTEXT_REQUEST_BYTES = 1_i64 * 1024_i64 * 1024_i64

      getter extensions : Registry
      getter invoker : Invoker
      getter grants : Permissions::GrantPolicy
      getter capabilities : API::CapabilityBroker
      getter events : EventBus

      def initialize(@extensions : Registry, @invoker : Invoker, @grants : Permissions::GrantPolicy, @capabilities : API::CapabilityBroker, @events : EventBus)
      end

      def messages_for(session : Session, tools : Array(ToolSpec)) : Array(Message)
        blocks = [] of ContextBlock
        extensions.enabled(grants).each do |manifest|
          next unless grants.for_extension(manifest.name).allows_context?(manifest.permissions)

          manifest.context_providers.each do |contribution|
            begin
              next unless approve_context(manifest.name, session)

              request = ContextRequest.new(session.id, session.messages, tools, blocks.dup)
              encoded_request = request.to_json
              if encoded_request.bytesize > MAX_CONTEXT_REQUEST_BYTES
                report_error(manifest.name, "context request exceeds #{MAX_CONTEXT_REQUEST_BYTES} bytes")
                next
              end
              response = invoker.invoke(
                manifest,
                "context",
                contribution.name,
                RawJSON.new(encoded_request),
                session: session
              )
              unless response.ok
                report_error(manifest.name, response.error || "context provider failed")
                next
              end

              patch = response.result.try { |value| ContextPatch.from_json(value.raw) } || ContextPatch.new
              apply_patch(blocks, patch, manifest.name)
            rescue ex
              report_error(manifest.name, "context provider failed: #{ex.message || ex.class.name}")
            end
          end
        end

        blocks.map { |block| Message.system(block.content) } + session.messages
      end

      private def approve_context(extension_id : String, session : Session) : Bool
        request = API::CapabilityRequest.new(
          "context-#{Random::Secure.hex(12)}",
          extension_id,
          "context.modify",
          session.id,
          "Read and modify model context for this session"
        )
        capabilities.authorize(request)
      end

      private def apply_patch(blocks : Array(ContextBlock), patch : ContextPatch, extension_id : String) : Nil
        candidate = blocks.dup
        patch.remove.each do |id|
          candidate.reject! { |block| block.id == id }
        end

        patch.add.each do |input|
          raise ArgumentError.new("invalid context block id") unless input.id.matches?(/\A[A-Za-z0-9._:-]{1,128}\z/)
          raise ArgumentError.new("context block exceeds #{MAX_CONTEXT_BLOCK_BYTES} bytes") if input.content.bytesize > MAX_CONTEXT_BLOCK_BYTES

          id = "extension/#{extension_id}/#{input.id}"
          candidate.reject! { |block| block.id == id }
          raise ArgumentError.new("too many context blocks") if candidate.size >= MAX_CONTEXT_BLOCKS
          candidate << ContextBlock.new(id, extension_id, input.content)
        end
        blocks.clear
        blocks.concat(candidate)
      end

      private def report_error(extension_id : String, message : String) : Nil
        events.emit(Event.new("extension.context.error", JSON.parse({
          "extension_id" => extension_id,
          "message"      => message,
        }.to_json), extension_id))
      end
    end
  end
end
