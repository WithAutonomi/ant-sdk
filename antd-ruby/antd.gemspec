# frozen_string_literal: true

require_relative "lib/antd/version"

Gem::Specification.new do |spec|
  spec.name          = "antd"
  spec.version       = Antd::VERSION
  spec.authors       = ["MaidSafe"]
  spec.email         = ["dev@maidsafe.net"]

  spec.summary       = "Ruby SDK for the antd daemon"
  spec.description   = "REST client for the antd daemon — the gateway to the Autonomi decentralized network."
  spec.homepage      = "https://github.com/maidsafe/ant-sdk"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.1"

  spec.files         = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # Zero runtime deps — Net::HTTP, JSON, Base64 are stdlib

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "webmock",  "~> 3.0"
end
