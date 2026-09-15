# frozen_string_literal: true

require_relative "lib/antd/version"

Gem::Specification.new do |spec|
  spec.name          = "antd"
  spec.version       = Antd::VERSION
  spec.authors       = ["WithAutonomi"]
  spec.email         = ["dev@autonomi.com"]

  spec.summary       = "Ruby client for the antd daemon (Autonomi network)"
  spec.description   = "Store and fetch data on the Autonomi decentralized network through a running antd daemon. " +
                       "Zero-dependency REST client; optional gRPC transport when the grpc gem is installed."
  spec.homepage      = "https://github.com/WithAutonomi/ant-sdk/tree/main/antd-ruby"
  spec.licenses      = ["MIT", "Apache-2.0"]

  spec.metadata = {
    "homepage_uri"          => spec.homepage,
    "source_code_uri"       => "https://github.com/WithAutonomi/ant-sdk/tree/main/antd-ruby",
    "documentation_uri"     => "https://github.com/WithAutonomi/ant-sdk/tree/main/antd-ruby#readme",
    "bug_tracker_uri"       => "https://github.com/WithAutonomi/ant-sdk/issues",
    "changelog_uri"         => "https://github.com/WithAutonomi/ant-sdk/releases",
    "rubygems_mfa_required" => "true"
  }

  spec.required_ruby_version = ">= 3.1"

  spec.files         = Dir["lib/**/*.rb", "README.md", "LICENSE-MIT", "LICENSE-APACHE"]
  spec.require_paths = ["lib"]

  # Zero runtime deps for REST — Net::HTTP, JSON, Base64 are stdlib
  # gRPC transport is optional; install the grpc gem to use GrpcClient
  spec.add_development_dependency "grpc",     "~> 1.60"
  spec.add_development_dependency "grpc-tools", "~> 1.60"

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "webmock",  "~> 3.0"

  # External-signer example (examples/07_external_signer.rb) only — Ruby
  # EVM client + ABI encoder. Not a runtime dep of the antd SDK itself.
  spec.add_development_dependency "eth",      "~> 0.5"
end
