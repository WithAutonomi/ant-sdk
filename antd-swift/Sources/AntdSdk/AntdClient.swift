import Foundation

/// Factory for creating Autonomi SDK clients.
///
/// ```swift
/// let client = AntdClient.createRest()
/// let health = try await client.health()
/// ```
public enum AntdClient {

    /// Create a REST client connecting to the antd daemon.
    /// - Parameters:
    ///   - baseURL: Base URL of the antd REST API (default: http://localhost:8082)
    ///   - timeout: Request timeout in seconds (default: 300)
    public static func createRest(
        baseURL: String = "http://localhost:8082",
        timeout: TimeInterval = 300
    ) -> AntdClientProtocol {
        AntdRestClient(baseURL: baseURL, timeout: timeout)
    }

    /// Create a gRPC client connecting to the antd daemon.
    /// - Parameter target: gRPC target address (default: localhost:50051)
    public static func createGrpc(target: String = "localhost:50051") -> AntdClientProtocol {
        AntdGrpcClient(target: target)
    }

    /// Create a client using the specified transport.
    /// - Parameters:
    ///   - transport: "rest" or "grpc"
    ///   - endpoint: Optional custom endpoint override
    public static func create(transport: String = "rest", endpoint: String? = nil) -> AntdClientProtocol {
        switch transport.lowercased() {
        case "rest":
            return createRest(baseURL: endpoint ?? "http://localhost:8082")
        case "grpc":
            return createGrpc(target: endpoint ?? "localhost:50051")
        default:
            fatalError("Unknown transport: \(transport). Use 'rest' or 'grpc'.")
        }
    }
}
