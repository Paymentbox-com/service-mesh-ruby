# frozen_string_literal: true

module ServiceMesh
  class Error < StandardError; end

  # Raised for misuse of the contract. Transport errors pass through as the
  # transport library's own exceptions.
  class KindMismatch < Error; end

  class InvalidTarget < Error; end

  class NoDeploymentGroup < Error
    def initialize(msg = "config #{DEPLOYMENT_GROUP_KEY} is required") = super
  end
end
