# service-mesh-ruby

The Ruby contract for the
[Service Mesh API Specification](https://github.com/Paymentbox-com/service-mesh-api),
packaged as the gem `service_mesh`. It holds what every transport and every
caller must agree on, and nothing that moves bytes. Transports are separate
gems that depend on it and implement `Client` and `Runtime`.

## Install

```ruby
# Gemfile
gem "service_mesh"
```

Requires Ruby 3.3 or newer. The gem has no runtime dependencies.

## What it fixes

- The value types from the specification, as `Data`: `ServiceMesh::Target`
  (`segments`, `kind`, `metadata`), `ServiceMap` (`targets`), `Message`
  (`target`, `metadata`, `payload`), `Endpoint` and `Subscriber` (`target`,
  `metadata`, `handler`). Kinds are `:route` and `:topic`. `Message#payload`
  is always `Encoding::BINARY`. `Target#same_channel?` compares segments and
  kind and ignores metadata.
- The configuration keys the specification defines: `DEPLOYMENT_GROUP_KEY`,
  `CONSUMER_GROUP_KEY`, and the value `CONSUMER_GROUP_NONE`.
- The contract errors, under `ServiceMesh::Error`: `KindMismatch`,
  `InvalidTarget`, `NoDeploymentGroup`.
- A conformance suite a transport runs against its own `Client` and
  `Runtime`.

`Client` and `Runtime` are duck types. The specification names their methods;
a transport satisfies the contract by responding to them and by passing the
conformance suite.

## Transports

- NATS: [service-mesh-nats-ruby](https://github.com/Paymentbox-com/service-mesh-nats-ruby),
  gem `service_mesh_nats`.

The Go counterpart of this gem is
[service-mesh-go](https://github.com/Paymentbox-com/service-mesh-go).

## Usage

Code written against the contract works with any transport. It receives a
client and a target and never learns which transport is underneath.

```ruby
require "service_mesh"

LOOKUP = ServiceMesh::Target.new(segments: %w[accounts lookup], kind: :route)

def lookup(client, id)
  reply = client.request(ServiceMesh::Message.new(target: LOOKUP, payload: id))
  reply.payload
end
```

The transport is chosen where the client is built, once per process.

## Conformance

A transport includes the shared examples from its own spec suite and supplies
constructors and a pair of valid targets:

```ruby
require "service_mesh/rspec"

RSpec.describe MyTransport do
  it_behaves_like "a service mesh transport" do
    let(:new_runtime) do
      ->(config, map, endpoints:, subscribers:) { MyTransport::Runtime.new(config, map, endpoints:, subscribers:) }
    end
    let(:new_client) { ->(config, map) { MyTransport::Client.new(config, map) } }
    let(:runtime_config) { {"deployment_group" => "test", "url" => url} }
    let(:client_config) { {"url" => url} }
    let(:route_target) { ServiceMesh::Target.new(segments: %w[test echo], kind: :route) }
    let(:topic_target) { ServiceMesh::Target.new(segments: %w[test event], kind: :topic) }
  end
end
```

The suite covers kind checks, the deployment group requirement, request and
reply with metadata both ways, publish, the consumer-group delivery
permutations across two runtimes, the runtime-owned client outside the running
window, the lifecycle state machine, and drain completing and expiring.
Anything that names a transport's own errors, config keys, or address syntax
stays in the transport's specs.

## Development

```
mise install
just install
just check      # lint, test, build
```

## Tests

```
just test
```
