import Foundation
import AntdSdk

@main
struct Examples {
    static func main() async {
        let example = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "all"

        do {
            switch example {
            case "1": try await example01Connect()
            case "2": try await example02Data()
            case "3": try await example03Chunks()
            case "4": try await example04Files()
            case "5": try await example06PrivateData()
            case "all":
                try await example01Connect()
                try await example02Data()
                try await example03Chunks()
                try await example04Files()
                try await example06PrivateData()
            default:
                print("Unknown example: \(example). Use 1-5 or 'all'.")
            }
        } catch {
            print("Error: \(error)")
        }
    }
}

func randomHex(_ byteCount: Int = 32) -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
    return bytes.map { String(format: "%02x", $0) }.joined()
}

/// Example 01: Connect to antd daemon and check health.
func example01Connect() async throws {
    print("=== Example 01: Connect ===")
    let client = AntdClient.createRest()

    let status = try await client.health()
    print("Daemon healthy: \(status.ok)")
    print("Network: \(status.network)")

    guard status.ok else { throw AntdError("antd daemon is not healthy") }
    print("Connection OK!\n")
}

/// Example 02: Store and retrieve public data, with cost estimation.
func example02Data() async throws {
    print("=== Example 02: Public Data ===")
    let client = AntdClient.createRest()

    let payload = "Hello, Autonomi network!".data(using: .utf8)!

    let est = try await client.dataCost(payload)
    print("Estimate: \(est.fileSize) bytes in \(est.chunkCount) chunks, storage \(est.cost) atto, gas \(est.estimatedGasCostWei) wei, mode \(est.paymentMode)")

    let result = try await client.dataPutPublic(payload)
    print("Stored at address: \(result.address)")
    print("Actual cost: \(result.cost) atto tokens")

    let data = try await client.dataGetPublic(address: result.address)
    let text = String(data: data, encoding: .utf8)!
    print("Retrieved: \(text)")

    guard data == payload else { throw AntdError("Round-trip mismatch!") }
    print("Public data round-trip OK!\n")
}

/// Example 03: Store and retrieve raw chunks.
func example03Chunks() async throws {
    print("=== Example 03: Chunks ===")
    let client = AntdClient.createRest()

    let rawData = "Raw chunk content for direct storage".data(using: .utf8)!

    let result = try await client.chunkPut(rawData)
    print("Chunk stored at: \(result.address)")
    print("Cost: \(result.cost) atto tokens")

    let retrieved = try await client.chunkGet(address: result.address)
    print("Retrieved \(retrieved.count) bytes")

    guard retrieved == rawData else { throw AntdError("Chunk round-trip mismatch!") }
    print("Chunk round-trip OK!\n")
}

/// Example 04: Upload and download files.
func example04Files() async throws {
    print("=== Example 04: Files ===")
    let client = AntdClient.createRest()

    let srcPath = NSTemporaryDirectory() + "antd-example-\(UUID().uuidString).txt"
    try "Hello from a file on Autonomi!".write(toFile: srcPath, atomically: true, encoding: .utf8)

    defer { try? FileManager.default.removeItem(atPath: srcPath) }

    let est = try await client.fileCost(path: srcPath)
    print("Estimate: \(est.fileSize) bytes in \(est.chunkCount) chunks, storage \(est.cost) atto, gas \(est.estimatedGasCostWei) wei, mode \(est.paymentMode)")

    let result = try await client.fileUploadPublic(path: srcPath)
    print("File uploaded to: \(result.address)")
    print("Storage cost: \(result.storageCostAtto) atto, gas: \(result.gasCostWei) wei")
    print("Chunks stored: \(result.chunksStored), payment mode: \(result.paymentModeUsed)")

    let destPath = srcPath + ".downloaded"
    try await client.fileDownloadPublic(address: result.address, destPath: destPath)
    print("Downloaded to: \(destPath)")

    let content = try String(contentsOfFile: destPath, encoding: .utf8)
    print("Content: \(content)")
    try? FileManager.default.removeItem(atPath: destPath)

    print("File upload/download OK!\n")
}

/// Example 05: Private (encrypted) data round-trip.
func example06PrivateData() async throws {
    print("=== Example 06: Private Data ===")
    let client = AntdClient.createRest()

    let secretMessage = "This message is encrypted on the network".data(using: .utf8)!

    let result = try await client.dataPutPrivate(secretMessage)
    let dataMap = result.address
    print("Data map: \(dataMap)")
    print("Cost: \(result.cost) atto tokens")

    let retrieved = try await client.dataGetPrivate(dataMap: dataMap)
    print("Decrypted: \(String(data: retrieved, encoding: .utf8)!)")

    guard retrieved == secretMessage else { throw AntdError("Private data round-trip mismatch!") }

    print("Private data round-trip OK!\n")
}
