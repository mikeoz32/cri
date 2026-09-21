require "random/secure"

module Cri
  module API
    enum ApprovalDecision
      Deny
      Allow

      def allowed? : Bool
        self == Allow
      end
    end

    class CapabilityRequest
      getter id : String
      getter actor : String
      getter capability : String
      getter target : String
      getter reason : String

      def initialize(@id : String, @actor : String, @capability : String, @target : String, @reason : String)
      end

      def to_json(json : JSON::Builder)
        json.object do
          json.field "id", id
          json.field "actor", actor
          json.field "capability", capability
          json.field "target", target
          json.field "reason", reason
        end
      end
    end

    # A one-shot, fiber-friendly approval result. `await` yields the current
    # fiber on Channel.receive instead of blocking the scheduler thread.
    class PendingApproval
      getter request : CapabilityRequest
      @result : Channel(ApprovalDecision)
      @resolved = false
      @mutex = Mutex.new

      def initialize(@request : CapabilityRequest)
        @result = Channel(ApprovalDecision).new(1)
      end

      def resolve(decision : ApprovalDecision)
        should_send = @mutex.synchronize do
          next false if @resolved
          @resolved = true
          true
        end
        @result.send(decision) if should_send
      end

      def await : ApprovalDecision
        @result.receive
      end
    end

    abstract class ApprovalBackend
      abstract def request(pending : PendingApproval)
      abstract def resolve(id : String, decision : ApprovalDecision) : Bool
    end

    class DenyAllBackend < ApprovalBackend
      def request(pending : PendingApproval)
        pending.resolve(ApprovalDecision::Deny)
      end

      def resolve(id : String, decision : ApprovalDecision) : Bool
        false
      end
    end

    class AllowAllBackend < ApprovalBackend
      def request(pending : PendingApproval)
        pending.resolve(ApprovalDecision::Allow)
      end

      def resolve(id : String, decision : ApprovalDecision) : Bool
        false
      end
    end

    # Emits approval.requested events. A TUI/CLI/API client resolves the
    # request through CapabilityBroker#resolve using the request id.
    class EventApprovalBackend < ApprovalBackend
      getter events : EventBus
      @pending = {} of String => PendingApproval
      @mutex = Mutex.new

      def initialize(@events : EventBus)
      end

      def request(pending : PendingApproval)
        @mutex.synchronize { @pending[pending.request.id] = pending }
        events.emit(Event.new("approval.requested", JSON.parse(pending.request.to_json), pending.request.id))
      end

      def resolve(id : String, decision : ApprovalDecision) : Bool
        pending = @mutex.synchronize { @pending.delete(id) }
        return false unless pending
        pending.resolve(decision)
        true
      end
    end

    class CapabilityBroker
      getter backend : ApprovalBackend

      def self.deny_all : self
        new(DenyAllBackend.new)
      end

      def self.allow_all : self
        new(AllowAllBackend.new)
      end

      def initialize(@backend : ApprovalBackend)
      end

      def authorize(request : CapabilityRequest) : Bool
        pending = PendingApproval.new(request)
        backend.request(pending)
        pending.await.allowed?
      end

      def resolve(id : String, decision : ApprovalDecision) : Bool
        backend.resolve(id, decision)
      end
    end
  end
end
