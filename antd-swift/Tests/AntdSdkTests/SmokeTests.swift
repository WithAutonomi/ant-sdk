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

        let put = PutResult(cost: "100", address: "abc123")
        XCTAssertEqual(put.cost, "100")
        XCTAssertEqual(put.address, "abc123")

        let desc = GraphDescendant(publicKey: "pk", content: "content")
        let entry = GraphEntry(owner: "owner", parents: ["p1"], content: "c", descendants: [desc])
        XCTAssertEqual(entry.parents.count, 1)
        XCTAssertEqual(entry.descendants.count, 1)

        let archiveEntry = ArchiveEntry(path: "/file.txt", address: "addr", created: 1000, modified: 2000, size: 512)
        let archive = Archive(entries: [archiveEntry])
        XCTAssertEqual(archive.entries.count, 1)
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
