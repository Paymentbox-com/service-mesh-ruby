# frozen_string_literal: true

module ServiceMesh
  KINDS = %i[route topic].freeze

  # Configuration keys the specification defines. Everything else belongs to
  # a transport. DEPLOYMENT_GROUP_KEY is runtime configuration, and nothing
  # else carries it. CONSUMER_GROUP_KEY is Endpoint and Subscriber metadata;
  # when it is unset or empty, the runtime's deployment group applies, and
  # CONSUMER_GROUP_NONE means no group. A Target carries neither.
  DEPLOYMENT_GROUP_KEY = "deployment_group"
  CONSUMER_GROUP_KEY = "consumer_group"
  CONSUMER_GROUP_NONE = "none"

  # Metadata keys that start with RESERVED_PREFIX belong to transports and
  # protocol layers, and application code does not set them. A key a
  # transport defines for itself continues with the transport's name, such as
  # "Mesh-Nats-". A transport may use any of the keys below, and one that does
  # follows the meaning and format given here.
  RESERVED_PREFIX = "Mesh-"

  # Set by the serving transport on a reply when the Endpoint's handler
  # failed. The value is the failure's text.
  HANDLER_ERROR_KEY = "Mesh-Handler-Error"

  # Set by the requesting transport on a request. The value is how long the
  # caller waits for the reply, as a whole number of milliseconds.
  TIMEOUT_KEY = "Mesh-Timeout"

  # Set by the receiving transport on a message it hands to a handler. The
  # value is when the handler's result stops mattering, in RFC 3339 with
  # fractional seconds.
  DEADLINE_KEY = "Mesh-Deadline"

  # Set by the receiving transport on a message it hands to a handler. The
  # value is which delivery of the message this is, starting at 1. It is
  # absent when the transport does not track deliveries.
  DELIVERY_ATTEMPT_KEY = "Mesh-Delivery-Attempt"

  # Set by the publisher or caller. The value is an ID that stays the same
  # when the same message is sent again, so handlers can recognize repeats.
  MESSAGE_ID_KEY = "Mesh-Message-Id"

  # Identifies a receiving channel on the mesh. A transport assembles the
  # segments into its own address; that string never leaves the transport.
  Target = Data.define(:segments, :kind, :metadata) do
    def initialize(segments:, kind:, metadata: {})
      raise KindMismatch, "kind must be one of #{KINDS.inspect}, got #{kind.inspect}" unless KINDS.include?(kind)

      super(segments: Array(segments).map(&:to_s).freeze, kind: kind, metadata: metadata.to_h.freeze)
    end

    # Same channel: same segments and kind. Metadata is configuration.
    def same_channel?(other)
      segments == other.segments && kind == other.kind
    end
  end

  # Every Target reachable over one transport.
  ServiceMap = Data.define(:targets) do
    def initialize(targets: [])
      super(targets: Array(targets).freeze)
    end
  end

  # What travels between services. Payload is always BINARY encoded. Metadata
  # keys that start with RESERVED_PREFIX belong to transports and protocol
  # layers.
  Message = Data.define(:target, :metadata, :payload) do
    def initialize(target:, metadata: {}, payload: "")
      super(target: target, metadata: metadata.to_h.freeze, payload: payload.to_s.b.freeze)
    end
  end

  # A route target paired with a handler that returns a Message.
  Endpoint = Data.define(:target, :metadata, :handler) do
    def initialize(target:, handler:, metadata: {})
      super(target: target, metadata: metadata.to_h.freeze, handler: handler)
    end
  end

  # A topic target paired with a handler whose return value is ignored.
  Subscriber = Data.define(:target, :metadata, :handler) do
    def initialize(target:, handler:, metadata: {})
      super(target: target, metadata: metadata.to_h.freeze, handler: handler)
    end
  end
end
