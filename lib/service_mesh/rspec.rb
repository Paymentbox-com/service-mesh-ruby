# frozen_string_literal: true

require "rspec"
require "timeout"
require_relative "../service_mesh"

# Conformance suite. A transport includes it from its own specs:
#
#   require "service_mesh/rspec"
#
#   RSpec.describe MyTransport do
#     it_behaves_like "a service mesh transport" do
#       let(:new_runtime)    { ->(client, config, endpoints:, subscribers:) { MyTransport::Runtime.new(client, config, endpoints:, subscribers:) } }
#       let(:new_client)     { ->(config, map) { MyTransport::Client.new(config, map) } }
#       let(:runtime_config) { {"deployment_group" => "test", ...transport keys...} }
#       let(:client_config)  { {...transport keys...} }
#       let(:route_target)   { ServiceMesh::Target.new(segments: %w[test echo], kind: :route) }
#       let(:topic_target)   { ServiceMesh::Target.new(segments: %w[test event], kind: :topic) }
#
#       # Optional, each defaulting to an empty Hash.
#       let(:target_metadata)     { {...} } # merged under the metadata of each Target the suite builds
#       let(:endpoint_metadata)   { {...} } # merged under each Endpoint's metadata
#       let(:subscriber_metadata) { {...} } # merged under each Subscriber's metadata
#       let(:request_options)     { {...} } # options for every request
#       let(:publish_options)     { {...} } # options for every publish
#     end
#   end
#
# Every example here follows from the specification alone. Anything that
# names a transport's own errors, config keys, or address syntax belongs in
# the transport's specs.
RSpec.shared_examples "a service mesh transport" do
  let(:service_map) { ServiceMesh::ServiceMap.new }
  let(:wait) { 3 }
  let(:target_metadata) { {} }
  let(:endpoint_metadata) { {} }
  let(:subscriber_metadata) { {} }
  let(:request_options) { {} }
  let(:publish_options) { {} }

  def target(segments, kind, metadata: {})
    ServiceMesh::Target.new(segments: segments, kind: kind, metadata: target_metadata.merge(metadata))
  end

  def endpoint(target, handler, metadata: {})
    ServiceMesh::Endpoint.new(target: target, handler: handler, metadata: endpoint_metadata.merge(metadata))
  end

  def subscriber(target, handler, consumer_group: nil, metadata: {})
    ServiceMesh::Subscriber.new(target: target, handler: handler, consumer_group: consumer_group, metadata: subscriber_metadata.merge(metadata))
  end

  def request(msg, via: client)
    via.request(msg, request_options)
  end

  def publish(msg, via: client)
    via.publish(msg, publish_options)
  end

  def message(target, metadata: {}, payload: "")
    ServiceMesh::Message.new(target: target, metadata: metadata, payload: payload)
  end

  def config_for(group)
    runtime_config.merge(ServiceMesh::DEPLOYMENT_GROUP_KEY => group)
  end

  def build(config = runtime_config, endpoints: [], subscribers: [])
    new_runtime.call(new_client.call(client_config, service_map), config, endpoints: endpoints, subscribers: subscribers)
  end

  def serve(config = runtime_config, endpoints: [], subscribers: [])
    rt = build(config, endpoints: endpoints, subscribers: subscribers)
    rt.start
    @conformance_runtimes << rt
    rt
  end

  def wait_until
    Timeout.timeout(wait) { sleep 0.01 until yield }
  end

  before do
    @conformance_runtimes = []
    @conformance_threads = []
  end

  after do
    @conformance_threads.each(&:kill)
    @conformance_runtimes.each { |rt| rt.stop(wait) }
  end

  let(:client) { new_client.call(client_config, service_map) }
  after { client.close }

  describe "kind checks" do
    it "rejects a request to a topic" do
      expect { request(message(topic_target)) }.to raise_error(ServiceMesh::KindMismatch)
    end

    it "rejects a publish to a route" do
      expect { publish(message(route_target)) }.to raise_error(ServiceMesh::KindMismatch)
    end

    it "rejects an endpoint on a topic" do
      expect { build(endpoints: [endpoint(topic_target, ->(m) { m })]) }.to raise_error(ServiceMesh::KindMismatch)
    end

    it "rejects a subscriber on a route" do
      expect { build(subscribers: [subscriber(route_target, ->(m) { m })]) }.to raise_error(ServiceMesh::KindMismatch)
    end
  end

  describe "configuration" do
    it "requires a deployment group" do
      without = runtime_config.reject { |k, _| k == ServiceMesh::DEPLOYMENT_GROUP_KEY }
      expect { build(without) }.to raise_error(ServiceMesh::NoDeploymentGroup)
    end

    it "rejects an empty deployment group" do
      expect { build(config_for("")) }.to raise_error(ServiceMesh::NoDeploymentGroup)
    end
  end

  describe "request and reply" do
    it "round-trips payload and metadata both ways and ignores the reply's target" do
      seen = nil
      serve(endpoints: [endpoint(route_target, lambda { |m|
        seen = m
        message(topic_target, metadata: {"Reply-Key" => "reply-value"}, payload: m.payload.upcase)
      })])

      reply = request(message(route_target, metadata: {"Request-Key" => "request-value"}, payload: "hello"))

      expect(seen.target.same_channel?(route_target)).to be(true)
      expect(seen.metadata["Request-Key"]).to eq("request-value")
      expect(reply.payload).to eq("HELLO")
      expect(reply.payload.encoding).to eq(Encoding::BINARY)
      expect(reply.metadata["Reply-Key"]).to eq("reply-value")
      expect(reply.target.same_channel?(route_target)).to be(true)
    end

    it "carries an empty payload with no metadata" do
      serve(endpoints: [endpoint(route_target, ->(m) { m })])
      reply = request(message(route_target))
      expect([reply.payload, reply.metadata]).to eq(["", {}])
    end
  end

  describe "publish" do
    it "reaches a subscriber with payload and metadata" do
      got = Queue.new
      serve(subscribers: [subscriber(topic_target, ->(m) { got << m })])

      publish(message(topic_target, metadata: {"Event-Id" => "42"}, payload: "created"))

      m = Timeout.timeout(wait) { got.pop }
      expect(m.target.same_channel?(topic_target)).to be(true)
      expect([m.payload, m.metadata["Event-Id"]]).to eq(["created", "42"])
    end
  end

  describe "consumer groups" do
    none = ServiceMesh::CONSUMER_GROUP_NONE
    shared = "order-consumers"

    [
      ["same deployment, group unset: one instance handles it", %w[billing billing], [nil, nil], 1],
      ["different deployments, group unset: each deployment handles it", %w[billing audit], [nil, nil], 2],
      ["same deployment, none: every instance handles it", %w[billing billing], [none, none], 2],
      ["different deployments, shared named group: one instance handles it", %w[billing audit], [shared, shared], 1]
    ].each do |name, groups, consumer_groups, want|
      it name do
        count = Queue.new
        2.times do |i|
          serve(config_for(groups[i]), subscribers: [subscriber(topic_target, ->(_) { count << true }, consumer_group: consumer_groups[i])])
        end

        publish(message(topic_target))

        wait_until { count.size >= want }
        sleep 0.1 # let an unwanted extra delivery show up
        expect(count.size).to eq(want)
      end
    end

    it "ignores a group set on the target, which carries none" do
      count = Queue.new
      %w[a b].each do |group|
        t = target(topic_target.segments, :topic, metadata: {"consumer_group" => group})
        serve(config_for("same"), subscribers: [subscriber(t, ->(_) { count << true })])
      end

      publish(message(topic_target))

      wait_until { count.size >= 1 }
      sleep 0.1 # let an unwanted extra delivery show up
      expect(count.size).to eq(1)
    end
  end

  describe "a standalone client" do
    it "accepts no requests after close" do
      serve(endpoints: [endpoint(route_target, ->(m) { m })])
      own = new_client.call(client_config, service_map)

      expect(request(message(route_target), via: own).payload).to eq("")
      own.close
      expect { request(message(route_target), via: own) }.to raise_error(StandardError)
    end
  end

  describe "the runtime's client" do
    it "is the client the runtime was given, and stop closes it" do
      given = new_client.call(client_config, service_map)
      rt = new_runtime.call(given, runtime_config, endpoints: [endpoint(route_target, ->(m) { m })], subscribers: [])
      @conformance_runtimes << rt
      req = message(route_target)

      expect(rt.client).to equal(given)
      expect(rt.service_map).to equal(service_map)
      rt.start
      expect(request(req, via: given).payload).to eq("")
      rt.stop(1)
      expect { request(req, via: given) }.to raise_error(StandardError)
    end
  end

  describe "lifecycle" do
    it "moves created -> running -> stopped and does not restart" do
      rt = build
      @conformance_runtimes << rt

      expect(rt.running?).to be(false)
      expect(rt.stop(0)).to be(true)
      rt.start
      expect(rt.running?).to be(true)
      expect { rt.start }.to raise_error(StandardError)
      expect(rt.stop(1)).to be(true)
      expect(rt.running?).to be(false)
      expect(rt.stop(0)).to be(true)
      expect { rt.start }.to raise_error(StandardError)
    end

    it "rejects a negative drain" do
      expect { build.stop(-1) }.to raise_error(ArgumentError)
    end
  end

  describe "stop" do
    it "waits for an in-flight handler and the requester still gets the reply" do
      entered = Queue.new
      release = Queue.new
      rt = serve(endpoints: [endpoint(route_target, lambda { |_|
        entered << true
        release.pop
        message(route_target, payload: "done")
      })])

      reply = Thread.new { request(message(route_target)) }
      @conformance_threads << reply
      Timeout.timeout(wait) { entered.pop }

      stopped = Thread.new { rt.stop(wait) }
      sleep 0.2
      expect(stopped.alive?).to be(true)

      release << true
      expect(stopped.value).to be(true)
      expect(reply.value.payload).to eq("done")
    end

    it "returns false when the drain expires with a handler still running" do
      entered = Queue.new
      release = Queue.new
      rt = serve(endpoints: [endpoint(route_target, lambda { |_|
        entered << true
        release.pop
        message(route_target)
      })])

      @conformance_threads << Thread.new { request(message(route_target)) rescue nil } # rubocop:disable Style/RescueModifier
      Timeout.timeout(wait) { entered.pop }

      expect(rt.stop(0.1)).to be(false)
      release << true
    end
  end
end
