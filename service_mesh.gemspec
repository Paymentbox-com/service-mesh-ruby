# frozen_string_literal: true

require_relative "lib/service_mesh/version"

Gem::Specification.new do |spec|
  spec.name = "service_mesh"
  spec.version = ServiceMesh::VERSION
  spec.authors = ["Paymentbox"]
  spec.summary = "Ruby contract for the Service Mesh API Specification"
  spec.homepage = "https://github.com/Paymentbox-com/service-mesh-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"] + %w[README.md LICENSE]
  spec.require_paths = ["lib"]
end
