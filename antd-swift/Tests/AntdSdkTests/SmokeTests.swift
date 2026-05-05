import XCTest
@testable import AntdSdk

final class SmokeTests: XCTestCase {

    func testFactoryCreatesRestClient() {
        let client = AntdClient.createRest()
        XCTAssertTrue(client is AntdRestClient)
    }

    func testFactoryCreatesGrpcClient() {
        let client = AntdClient.createGrpc()
        XCTAssertTrue(client is AntdGrpcClient)
    }

    func testFactoryCreateWithTransportString() {
        let rest = AntdClient.create(transport: "rest")
        XCTAssertTrue(rest is AntdRestClient)

        let grpc = AntdClient.create(transport: "grpc")
        XCTAssertTrue(grpc is AntdGrpcClient)
    }

    func testModelsHaveCorrectStructure() {
        let health = HealthStatus(ok: true, network: "local")
        XCTAssertTrue(health.ok)
        XCTAssertEqual(health.network, "local")
        // Diagnostic fields default to empty / 0 for the 2-arg init,
        // so callers + pre-0.4.0 daemon responses both still work.
        XCTAssertEqual(health.version, "")
        XCTAssertEqual(health.evmNetwork, "")
        XCTAssertEqual(health.uptimeSeconds, 0)
        XCTAssertEqual(health.buildCommit, "")

        let fullHealth = HealthStatus(
            ok: true,
            network: "default",
            version: "0.4.0",
            evmNetwork: "arbitrum-one",
            uptimeSeconds: 42,
            buildCommit: "abcdef123456",
            paymentTokenAddress: "0xtoken",
            paymentVaultAddress: "0xvault"
        )
        XCTAssertEqual(fullHealth.version, "0.4.0")
        XCTAssertEqual(fullHealth.evmNetwork, "arbitrum-one")
        XCTAssertEqual(fullHealth.uptimeSeconds, 42)

        let put = PutResult(cost: "100", address: "abc123")
        XCTAssertEqual(put.cost, "100")
        XCTAssertEqual(put.address, "abc123")

    }

    func testErrorHierarchy() {
        let errors: [AntdError] = [
            NotFoundError("not found"),
            AlreadyExistsError("exists"),
            ForkError("fork"),
            BadRequestError("bad"),
            PaymentError("pay"),
            NetworkError("net"),
            TooLargeError("big"),
            InternalError("err"),
        ]

        for error in errors {
            XCTAssertTrue(error is AntdError)
        }

        XCTAssertEqual(NotFoundError("x").statusCode, 404)
        XCTAssertEqual(AlreadyExistsError("x").statusCode, 409)
        XCTAssertEqual(BadRequestError("x").statusCode, 400)
        XCTAssertEqual(PaymentError("x").statusCode, 402)
        XCTAssertEqual(NetworkError("x").statusCode, 502)
        XCTAssertEqual(TooLargeError("x").statusCode, 413)
        XCTAssertEqual(InternalError("x").statusCode, 500)
    }

    func testErrorMappingFromHTTPStatus() {
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(400, body: "bad") is BadRequestError)
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(402, body: "pay") is PaymentError)
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(404, body: "nf") is NotFoundError)
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(409, body: "exists") is AlreadyExistsError)
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(413, body: "big") is TooLargeError)
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(500, body: "err") is InternalError)
        XCTAssertTrue(ErrorMapping.fromHTTPStatus(502, body: "net") is NetworkError)
    }
}
