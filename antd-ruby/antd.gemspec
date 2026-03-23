# frozen_string_literal: true

require_relative "lib/antd/version"

Gem::Specification.new do |spec|
  spec.name          = "antd"
  spec.version       = Antd::VERSION
  spec.authors       = ["MaidSafe"]
  spec.email         = ["dev@maidsafe.net"]

  spec.summary       = "Ruby SDK for the antd daemon"
  spec.description   = "REST client for the antd daemon — the gateway to the Autonomi decentralized network."
  spec.homepage      = "https://github.com/WithAutonomi/ant-sdk"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.1"

  spec.files         = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # Zero runtime deps for REST — Net::HTTP, JSON, Base64 are stdlib
  # gRPC transport is optional; install the grpc gem to use GrpcClient
  spec.add_development_dependency "grpc",     "~> 1.60"
  spec.add_development_dependency "grpc-tools", "~> 1.60"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "webmock",  "~> 3.0"
end
