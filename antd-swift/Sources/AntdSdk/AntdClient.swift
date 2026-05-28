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
    ///
    /// > Requires macOS 15+ / iOS 18+ / tvOS 18+ / watchOS 11+ (grpc-swift 2.x).
    /// > Use ``createRest(baseURL:timeout:)`` on older platforms.
    ///
    /// - Parameter target: gRPC target address (default: localhost:50051)
    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
    public static func createGrpc(target: String = "localhost:50051") -> AntdClientProtocol {
        AntdGrpcClient(target: target)
    }

    /// Create a client using the specified transport.
    ///
    /// > `transport: "grpc"` requires macOS 15+ / iOS 18+ / tvOS 18+ / watchOS 11+.
    ///
    /// - Parameters:
    ///   - transport: "rest" or "grpc"
    ///   - endpoint: Optional custom endpoint override
    public static func create(transport: String = "rest", endpoint: String? = nil) -> AntdClientProtocol {
        switch transport.lowercased() {
        case "rest":
            return createRest(baseURL: endpoint ?? "http://localhost:8082")
        case "grpc":
            if #available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *) {
                return createGrpc(target: endpoint ?? "localhost:50051")
            } else {
                fatalError("gRPC transport requires macOS 15+ / iOS 18+. Use 'rest' on older platforms.")
            }
        default:
            fatalError("Unknown transport: \(transport). Use 'rest' or 'grpc'.")
        }
    }
}
