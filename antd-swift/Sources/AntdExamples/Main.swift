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
            case "5": try await example05Pointers()
            case "6": try await example06Scratchpads()
            case "7": try await example07Graph()
            case "8": try await example08Registers()
            case "9": try await example09Vaults()
            case "10": try await example10PrivateData()
            case "all":
                try await example01Connect()
                try await example02Data()
                try await example03Chunks()
                try await example04Files()
                try await example05Pointers()
                try await example06Scratchpads()
                try await example07Graph()
                try await example08Registers()
                try await example09Vaults()
                try await example10PrivateData()
            default:
                print("Unknown example: \(example). Use 1-10 or 'all'.")
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

    let cost = try await client.dataCost(payload)
    print("Estimated cost: \(cost) atto tokens")

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

    let cost = try await client.fileCost(path: srcPath)
    print("File upload cost estimate: \(cost) atto tokens")

    let result = try await client.fileUploadPublic(path: srcPath)
    print("File uploaded to: \(result.address)")
    print("Actual cost: \(result.cost) atto tokens")

    let destPath = srcPath + ".downloaded"
    try await client.fileDownloadPublic(address: result.address, destPath: destPath)
    print("Downloaded to: \(destPath)")

    let content = try String(contentsOfFile: destPath, encoding: .utf8)
    print("Content: \(content)")
    try? FileManager.default.removeItem(atPath: destPath)

    print("File upload/download OK!\n")
}

/// Example 05: Create, read, and update mutable pointers.
func example05Pointers() async throws {
    print("=== Example 05: Pointers ===")
    let client = AntdClient.createRest()
    let secretKey = randomHex()

    let dataV1 = try await client.dataPutPublic("version 1".data(using: .utf8)!)
    let dataV2 = try await client.dataPutPublic("version 2".data(using: .utf8)!)

    let targetV1 = PointerTarget(kind: "chunk", address: dataV1.address)
    let ptr = try await client.pointerCreate(ownerSecretKey: secretKey, target: targetV1)
    print("Pointer created at: \(ptr.address)")

    var pointer = try await client.pointerGet(address: ptr.address)
    print("Points to: \(pointer.target.kind) @ \(pointer.target.address)")
    print("Counter: \(pointer.counter)")

    let exists = try await client.pointerExists(address: ptr.address)
    print("Pointer exists: \(exists)")

    let targetV2 = PointerTarget(kind: "chunk", address: dataV2.address)
    try await client.pointerUpdate(ownerSecretKey: secretKey, target: targetV2)
    print("Pointer updated to v2")

    pointer = try await client.pointerGet(address: ptr.address)
    print("Now points to: \(pointer.target.address)")

    print("Pointer CRUD OK!\n")
}

/// Example 06: Create, read, and update versioned scratchpads.
func example06Scratchpads() async throws {
    print("=== Example 06: Scratchpads ===")
    let client = AntdClient.createRest()
    let secretKey = randomHex()

    let initialData = "scratchpad v1 data".data(using: .utf8)!
    let contentType: UInt64 = 1
    let result = try await client.scratchpadCreate(ownerSecretKey: secretKey, contentType: contentType, data: initialData)
    print("Scratchpad created at: \(result.address)")
    print("Cost: \(result.cost) atto tokens")

    var pad = try await client.scratchpadGet(address: result.address)
    print("Data encoding: \(pad.dataEncoding)")
    print("Counter: \(pad.counter)")
    print("Data length: \(pad.data.count) bytes")

    let exists = try await client.scratchpadExists(address: result.address)
    print("Scratchpad exists: \(exists)")

    let updatedData = "scratchpad v2 data".data(using: .utf8)!
    try await client.scratchpadUpdate(ownerSecretKey: secretKey, contentType: contentType, data: updatedData)
    print("Scratchpad updated")

    pad = try await client.scratchpadGet(address: result.address)
    print("Counter after update: \(pad.counter)")

    print("Scratchpad CRUD OK!\n")
}

/// Example 07: Graph entry (DAG node) operations.
func example07Graph() async throws {
    print("=== Example 07: Graph ===")
    let client = AntdClient.createRest()
    let secretKey = randomHex()

    let content = randomHex()
    let result = try await client.graphEntryPut(
        ownerSecretKey: secretKey, parents: [], content: content, descendants: [])
    print("Graph entry created at: \(result.address)")
    print("Cost: \(result.cost) atto tokens")

    let entry = try await client.graphEntryGet(address: result.address)
    print("Owner: \(entry.owner)")
    print("Content: \(entry.content)")
    print("Parents: \(entry.parents.count)")
    print("Descendants: \(entry.descendants.count)")

    let exists = try await client.graphEntryExists(address: result.address)
    print("Graph entry exists: \(exists)")

    let cost = try await client.graphEntryCost(publicKey: secretKey)
    print("Cost estimate for new entry: \(cost) atto tokens")

    print("Graph entry operations OK!\n")
}

/// Example 08: Register create, read, and update.
func example08Registers() async throws {
    print("=== Example 08: Registers ===")
    let client = AntdClient.createRest()
    let secretKey = randomHex()

    let initialValue = String(repeating: "0", count: 64)
    let result = try await client.registerCreate(ownerSecretKey: secretKey, initialValue: initialValue)
    print("Register created at: \(result.address)")
    print("Cost: \(result.cost) atto tokens")

    var reg = try await client.registerGet(address: result.address)
    print("Current value: \(reg.value)")

    let newValue = randomHex()
    let updateResult = try await client.registerUpdate(ownerSecretKey: secretKey, newValue: newValue)
    print("Update cost: \(updateResult.cost) atto tokens")

    reg = try await client.registerGet(address: result.address)
    print("Updated value: \(reg.value)")

    print("Register CRUD OK!\n")
}

/// Example 09: Vault store and retrieve.
func example09Vaults() async throws {
    print("=== Example 09: Vaults ===")
    let client = AntdClient.createRest()
    let secretKey = randomHex()

    let payload = "Secret vault data that is encrypted".data(using: .utf8)!
    let contentType: UInt64 = 42
    let cost = try await client.vaultPut(secretKey: secretKey, data: payload, contentType: contentType)
    print("Vault store cost: \(cost) atto tokens")

    let vault = try await client.vaultGet(secretKey: secretKey)
    print("Content type: \(vault.contentType)")
    print("Data: \(String(data: vault.data, encoding: .utf8)!)")

    guard vault.data == payload else { throw AntdError("Vault round-trip mismatch!") }
    guard vault.contentType == contentType else { throw AntdError("Content type mismatch!") }

    print("Vault round-trip OK!\n")
}

/// Example 10: Private (encrypted) data round-trip.
func example10PrivateData() async throws {
    print("=== Example 10: Private Data ===")
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
