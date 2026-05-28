import XCTest
import GRPCCore
import GRPCNIOTransportHTTP2
@testable import AntdSdk

/// V2-286 in-process mock-server tests for `AntdGrpcClient.wallet*`.
/// Mirrors the antd-rust / antd-go / antd-py / antd-java / antd-kotlin /
/// antd-csharp / antd-ruby / antd-dart suites.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class GrpcWalletTests: XCTestCase {

    private func withMockServer<T: Sendable>(
        service: MockWalletService,
        _ body: @Sendable (AntdGrpcClient) async throws -> T
    ) async throws -> T {
        let transport = HTTP2ServerTransport.Posix(
            address: .ipv4(host: "127.0.0.1", port: 0),
            transportSecurity: .plaintext
        )
        return try await withGRPCServer(
            transport: transport,
            services: [service]
        ) { _ in
            let listening = try await transport.listeningAddress
            guard let port = listening.ipv4?.port else {
                XCTFail("expected an ipv4 listening address; got \(listening)")
                throw RPCError(code: .internalError, message: "no ipv4 listening address")
            }
            let client = AntdGrpcClient(target: "127.0.0.1:\(port)")
            return try await body(client)
        }
    }

    func testWalletAddressReturnsAddress() async throws {
        try await withMockServer(service: MockWalletService()) { client in
            let r = try await client.walletAddress()
            XCTAssertEqual(r.address, "0xabc1234567890abcdef1234567890abcdef123456")
        }
    }

    func testWalletBalanceReturnsBalances() async throws {
        try await withMockServer(service: MockWalletService()) { client in
            let r = try await client.walletBalance()
            XCTAssertEqual(r.balance, "1000000000000000000")
            XCTAssertEqual(r.gasBalance, "500000000000000000")
        }
    }

    func testWalletApproveReturnsTrue() async throws {
        try await withMockServer(service: MockWalletService()) { client in
            let approved = try await client.walletApprove()
            XCTAssertTrue(approved)
        }
    }

    /// Daemon emits gRPC `failedPrecondition` for "wallet not configured";
    /// the established mapping `ErrorMapping.fromGRPCStatus` surfaces this
    /// as `PaymentError`. (Semantic a bit off vs REST's 503 but matches
    /// every SDK.)
    func testWalletAddressUnconfiguredThrowsPaymentError() async throws {
        try await withMockServer(service: MockWalletService(unconfigured: true)) { client in
            do {
                _ = try await client.walletAddress()
                XCTFail("expected PaymentError")
            } catch let err as PaymentError {
                XCTAssertTrue(err.message.contains("wallet not configured"))
            } catch {
                XCTFail("expected PaymentError, got \(error)")
            }
        }
    }
}

/// Mock implementation of `WalletService` returning canned responses, or
/// `failedPrecondition` errors when `unconfigured == true`.
@available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, *)
final class MockWalletService: Antd_V1_WalletService.SimpleServiceProtocol, @unchecked Sendable {
    private let unconfigured: Bool

    init(unconfigured: Bool = false) {
        self.unconfigured = unconfigured
    }

    func getAddress(
        request: Antd_V1_GetWalletAddressRequest,
        context: ServerContext
    ) async throws -> Antd_V1_GetWalletAddressResponse {
        if unconfigured {
            throw RPCError(code: .failedPrecondition, message: "wallet not configured — set AUTONOMI_WALLET_KEY")
        }
        var resp = Antd_V1_GetWalletAddressResponse()
        resp.address = "0xabc1234567890abcdef1234567890abcdef123456"
        return resp
    }

    func getBalance(
        request: Antd_V1_GetWalletBalanceRequest,
        context: ServerContext
    ) async throws -> Antd_V1_GetWalletBalanceResponse {
        if unconfigured {
            throw RPCError(code: .failedPrecondition, message: "wallet not configured — set AUTONOMI_WALLET_KEY")
        }
        var resp = Antd_V1_GetWalletBalanceResponse()
        resp.balance = "1000000000000000000"
        resp.gasBalance = "500000000000000000"
        return resp
    }

    func approve(
        request: Antd_V1_WalletApproveRequest,
        context: ServerContext
    ) async throws -> Antd_V1_WalletApproveResponse {
        if unconfigured {
            throw RPCError(code: .failedPrecondition, message: "wallet not configured — set AUTONOMI_WALLET_KEY")
        }
        var resp = Antd_V1_WalletApproveResponse()
        resp.approved = true
        return resp
    }
}
