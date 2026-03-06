package com.autonomi.sdk

import java.time.Duration

/**
 * Factory for creating Autonomi SDK clients.
 *
 * ```kotlin
 * val client = AntdClient.createRest()
 * val health = client.health()
 * ```
 */
object AntdClient {

    /**
     * Create a REST client connecting to the antd daemon.
     * @param baseUrl Base URL of the antd REST API (default: http://localhost:8080)
     * @param timeout Request timeout (default: 300 seconds)
     */
    @JvmStatic
    @JvmOverloads
    fun createRest(
        baseUrl: String = "http://localhost:8080",
        timeout: Duration = Duration.ofSeconds(300),
    ): IAntdClient = AntdRestClient(baseUrl, timeout)

    /**
     * Create a gRPC client connecting to the antd daemon.
     * @param target gRPC target address (default: localhost:50051)
     */
    @JvmStatic
    @JvmOverloads
    fun createGrpc(target: String = "localhost:50051"): IAntdClient = AntdGrpcClient(target)

    /**
     * Create a client using the specified transport.
     * @param transport "rest" or "grpc"
     * @param endpoint Optional custom endpoint override
     */
    @JvmStatic
    @JvmOverloads
    fun create(transport: String = "rest", endpoint: String? = null): IAntdClient =
        when (transport.lowercase()) {
            "rest" -> createRest(endpoint ?: "http://localhost:8080")
            "grpc" -> createGrpc(endpoint ?: "localhost:50051")
            else -> throw IllegalArgumentException("Unknown transport: $transport. Use 'rest' or 'grpc'.")
        }
}
