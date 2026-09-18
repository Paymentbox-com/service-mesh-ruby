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
#       let(:new_runtime)    { ->(config, map, endpoints:, subscribers:) { MyTransport::Runtime.new(config, map, endpoints:, subscribers:) } }
#       let(:new_client)     { ->(config) { MyTransport::Client.new(config) } }
#       let(:runtime_config) { {"deployment_group" => "test", ...transport keys...} }
#       let(:client_config)  { {...transport keys...} }
#       let(:route_target)   { ServiceMesh::Target.new(segments: %w[test echo], kind: :route) }
#       let(:topic_target)   { ServiceMesh::Target.new(segments: %w[test event], kind: :topic) }
#     end
#   end
#
# Every example here follows from the specification alone. Anything that
# names a transport's own errors, config keys, or address syntax belongs in
# the transport's specs.
RSpec.shared_examples "a service mesh transport" do
  let(:service_map) { ServiceMesh::ServiceMap.new }
  let(:wait) { 3 }

  def endpoint(target, handler, metadata: {})
    ServiceMesh::Endpoint.new(target: target, handler: handler, metadata: metadata)
  end

  def subscriber(target, handler, metadata: {})
    ServiceMesh::Subscriber.new(target: target, handler: handler, metadata: metadata)
  end

  def message(target, metadata: {}, payload: "")
    ServiceMesh::Message.new(target: target, metadata: metadata, payload: payload)
  end

  def config_for(group)
    runtime_config.merge(ServiceMesh::DEPLOYMENT_GROUP_KEY => group)
  end

  def build(config = runtime_config, endpoints: [], subscribers: [])
    new_runtime.call(config, service_map, endpoints: endpoints, subscribers: subscribers)
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

  let(:client) { new_client.call(client_config) }
  after { client.close }

  describe "kind checks" do
    it "rejects a request to a topic" do
      expect { client.request(message(topic_target)) }.to raise_error(ServiceMesh::KindMismatch)
    end

    it "rejects a publish to a route" do
      expect { client.publish(message(route_target)) }.to raise_error(ServiceMesh::KindMismatch)
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

      reply = client.request(message(route_target, metadata: {"Request-Key" => "request-value"}, payload: "hello"))

      expect(seen.target.same_channel?(route_target)).to be(true)
      expect(seen.metadata["Request-Key"]).to eq("request-value")
      expect(reply.payload).to eq("HELLO")
      expect(reply.payload.encoding).to eq(Encoding::BINARY)
      expect(reply.metadata["Reply-Key"]).to eq("reply-value")
      expect(reply.target.same_channel?(route_target)).to be(true)
    end

    it "carries an empty payload with no metadata" do
      serve(endpoints: [endpoint(route_target, ->(m) { m })])
      reply = client.request(message(route_target))
      expect([reply.payload, reply.metadata]).to eq(["", {}])
    end
  end

  describe "publish" do
    it "reaches a subscriber with payload and metadata" do
      got = Queue.new
      serve(subscribers: [subscriber(topic_target, ->(m) { got << m })])

      client.publish(message(topic_target, metadata: {"Event-Id" => "42"}, payload: "created"))

      m = Timeout.timeout(wait) { got.pop }
      expect(m.target.same_channel?(topic_target)).to be(true)
      expect([m.payload, m.metadata["Event-Id"]]).to eq(["created", "42"])
    end
  end

  describe "consumer groups" do
    none = {ServiceMesh::CONSUMER_GROUP_KEY => ServiceMesh::CONSUMER_GROUP_NONE}
    shared = {ServiceMesh::CONSUMER_GROUP_KEY => "order-consumers"}

    [
      ["same deployment, key absent: one instance handles it", %w[billing billing], [{}, {}], 1],
      ["different deployments, key absent: each deployment handles it", %w[billing audit], [{}, {}], 2],
      ["same deployment, none: every instance handles it", %w[billing billing], [none, none], 2],
      ["different deployments, shared named group: one instance handles it", %w[billing audit], [shared, shared], 1]
    ].each do |name, groups, metadata, want|
      it name do
        count = Queue.new
        2.times do |i|
          serve(config_for(groups[i]), subscribers: [subscriber(topic_target, ->(_) { count << true }, metadata: metadata[i])])
        end

        client.publish(message(topic_target))

        wait_until { count.size >= want }
        sleep 0.1 # let an unwanted extra delivery show up
        expect(count.size).to eq(want)
      end
    end

    it "honours a group set on the target rather than the binding" do
      count = Queue.new
      %w[a b].each do |group|
        t = ServiceMesh::Target.new(segments: topic_target.segments, kind: :topic, metadata: {ServiceMesh::CONSUMER_GROUP_KEY => group})
        serve(config_for("same"), subscribers: [subscriber(t, ->(_) { count << true })])
      end
      client.publish(message(topic_target))
      wait_until { count.size == 2 }
    end
  end

  describe "the runtime-owned client" do
    it "works only inside the running window" do
      rt = build(endpoints: [endpoint(route_target, ->(m) { m })])
      @conformance_runtimes << rt
      owned = rt.client
      req = message(route_target)

      expect { owned.request(req) }.to raise_error(StandardError)
      rt.start
      expect(owned.request(req).payload).to eq("")
      owned.close
      expect(owned.request(req).payload).to eq("")
      rt.stop(1)
      expect { owned.request(req) }.to raise_error(StandardError)
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

      reply = Thread.new { client.request(message(route_target)) }
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

      @conformance_threads << Thread.new { client.request(message(route_target)) rescue nil } # rubocop:disable Style/RescueModifier
      Timeout.timeout(wait) { entered.pop }

      expect(rt.stop(0.1)).to be(false)
      release << true
    end
  end
end
