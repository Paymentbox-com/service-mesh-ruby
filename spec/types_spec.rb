# frozen_string_literal: true

RSpec.describe ServiceMesh::Target do
  it "accepts each kind" do
    ServiceMesh::KINDS.each do |kind|
      expect(described_class.new(segments: %w[a], kind: kind).kind).to eq(kind)
    end
  end

  it "rejects an unknown kind" do
    expect { described_class.new(segments: %w[a], kind: :queue) }.to raise_error(ServiceMesh::KindMismatch)
  end

  it "coerces segments to frozen strings" do
    t = described_class.new(segments: [:a, 1], kind: :route)
    expect(t.segments).to eq(%w[a 1])
    expect(t.segments).to be_frozen
  end

  it "compares channels by segments and kind only" do
    a = described_class.new(segments: %w[x], kind: :route, metadata: {"k" => "1"})
    same = described_class.new(segments: %w[x], kind: :route)
    other_kind = described_class.new(segments: %w[x], kind: :topic)
    other_segments = described_class.new(segments: %w[x y], kind: :route)
    expect(a.same_channel?(same)).to be(true)
    expect(a.same_channel?(other_kind)).to be(false)
    expect(a.same_channel?(other_segments)).to be(false)
  end
end

RSpec.describe ServiceMesh::Message do
  let(:target) { ServiceMesh::Target.new(segments: %w[x], kind: :route) }

  it "forces a text payload to binary without changing its bytes" do
    m = described_class.new(target: target, payload: "héllo")
    expect(m.payload.encoding).to eq(Encoding::BINARY)
    expect(m.payload.bytesize).to eq(6)
  end

  it "leaves a binary payload as is" do
    raw = "\x00\xFF".b
    expect(described_class.new(target: target, payload: raw).payload).to eq(raw)
  end

  it "defaults to an empty payload and metadata" do
    m = described_class.new(target: target)
    expect([m.payload, m.metadata]).to eq(["", {}])
  end
end

RSpec.describe ServiceMesh::ServiceMap do
  it "defaults to no targets" do
    expect(described_class.new.targets).to eq([])
  end
end

RSpec.describe ServiceMesh::NoDeploymentGroup do
  it "names the missing key by default" do
    expect(described_class.new.message).to include(ServiceMesh::DEPLOYMENT_GROUP_KEY)
  end
end
