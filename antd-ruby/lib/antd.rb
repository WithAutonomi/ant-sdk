# frozen_string_literal: true

require_relative "antd/version"
require_relative "antd/models"
require_relative "antd/errors"
require_relative "antd/discover"
require_relative "antd/client"

# gRPC client is optional — requires the `grpc` gem and proto-generated stubs.
begin
  require_relative "antd/grpc_client"
rescue LoadError
  # grpc gem not installed; GrpcClient not available
end
