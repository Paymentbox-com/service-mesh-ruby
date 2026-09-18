# frozen_string_literal: true

require_relative "service_mesh/version"
require_relative "service_mesh/types"
require_relative "service_mesh/errors"

# Ruby contract for the Service Mesh API Specification. Transports implement
# Client and Runtime against these types; see service_mesh/rspec for the
# conformance suite a transport runs.
module ServiceMesh
end
