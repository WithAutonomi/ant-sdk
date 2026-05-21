// Minimal Linux smoke test that exercises the data round-trip. The full
// example suite lives in /tmp/Main.swift.macos-bak (uses Apples Security
// framework and pre-existing arity bugs that block compile on Linux).
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AntdSdk

@main
struct Examples {
    static func main() async {
        do {
            print("=== Example 02: Public Data ===")
            let client = AntdClient.createRest()

            let payload = "Hello, Autonomi network!".data(using: .utf8)!

            let est = try await client.dataCost(payload, paymentMode: .auto)
            print("Estimate: \(est.fileSize) bytes in \(est.chunkCount) chunks, storage \(est.cost) atto, gas \(est.estimatedGasCostWei) wei, mode \(est.paymentMode)")

            let result = try await client.dataPutPublic(payload, paymentMode: .auto)
            print("Stored at address: \(result.address)")
            print("Chunks stored: \(result.chunksStored), mode used: \(result.paymentModeUsed)")

            let data = try await client.dataGetPublic(address: result.address)
            let text = String(data: data, encoding: .utf8)!
            print("Retrieved: \(text)")

            guard data == payload else {
                throw AntdError("Round-trip mismatch!")
            }
            print("Public data round-trip OK!")
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    }
}
