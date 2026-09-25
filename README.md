# service-mesh-ruby

The Ruby contract for the
[Service Mesh API Specification](https://github.com/Paymentbox-com/service-mesh-api),
packaged as the gem `service_mesh`. It holds what every transport and every
caller must agree on, and nothing that moves bytes. Transports are separate
gems that depend on it and implement `Client` and `Runtime`.

The [gRPC Service Mesh API](https://github.com/Paymentbox-com/grpc-service-mesh-api) is a protocol layer that generates code against this contract from protobuf
definitions, through its Ruby library [grpc-service-mesh-ruby](https://github.com/Paymentbox-com/grpc-service-mesh-ruby). Other protocol layers may be implemented 
to do the same. 

## Install

```ruby
# Gemfile
gem "service_mesh"
```

Requires Ruby 3.3 or newer. The gem has no runtime dependencies.

## What it Implements

- The value types from the specification: `ServiceMesh::Target`, `ServiceMesh::ServiceMap`, 
  `ServiceMesh::Message`, `ServiceMesh::Endpoint` and `ServiceMesh::Subscriber`.
- Target Kinds are implemented as `:route` and `:topic`. A `Target` built with a kind outside the two
  raises `KindMismatch`.
- `Message#payload` is always `Encoding::BINARY`.
- `Target#same_channel?` compares segments and kind and ignores metadata. 
- The configuration keys the specification defines: `DEPLOYMENT_GROUP_KEY`,
  `CONSUMER_GROUP_KEY`, and the value `CONSUMER_GROUP_NONE`.
- The errors defined by the specification as `ServiceMesh::Error`: `ServiceMesh::KindMismatch`,
  `ServiceMesh::InvalidTarget`, `ServiceMesh::NoDeploymentGroup`.
- A conformance suite a transport runs against its own `Client` and
  `Runtime`.

`Client` and `Runtime` are duck types. The specification names their methods;
a transport satisfies the contract by responding to them and by passing the
conformance suite.

## Transports

- NATS: [service-mesh-nats-ruby](https://github.com/Paymentbox-com/service-mesh-nats-ruby),
  gem `service_mesh_nats`.

## Usage

A transport that implements Client and Runtime according to the specification will used the
types defined here.

```ruby
require "service_mesh"

TARGET = ServiceMesh::Target.new(segments: %w[accounts lookup], kind: :route)

def lookup(client, id)
  reply = client.request(ServiceMesh::Message.new(target: TARGET, payload: id))
  reply.payload
end
```

## Conformance

A transport implemented to use these types should include the shared examples defined in this
library in its own spec suite and supply its own constructors and a pair of valid targets:

```ruby
require "service_mesh/rspec"

RSpec.describe MyTransport do
  it_behaves_like "a service mesh transport" do
    let(:new_runtime) do
      ->(client, config, endpoints:, subscribers:) { MyTransport::Runtime.new(client, config, endpoints:, subscribers:) }
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
permutations across two runtimes, a standalone client refusing requests after
close, the runtime's client being the one it was given and closed by stop, the lifecycle state machine, and drain completing and expiring.
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
