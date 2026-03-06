package com.autonomi.examples

import com.autonomi.sdk.*
import kotlinx.coroutines.runBlocking
import java.io.File
import java.security.SecureRandom

fun main(args: Array<String>) = runBlocking {
    val example = args.firstOrNull() ?: "all"

    when (example) {
        "1" -> example01Connect()
        "2" -> example02Data()
        "3" -> example03Chunks()
        "4" -> example04Files()
        "5" -> example05Pointers()
        "6" -> example06Scratchpads()
        "7" -> example07Graph()
        "8" -> example08Registers()
        "9" -> example09Vaults()
        "10" -> example10PrivateData()
        "all" -> {
            example01Connect()
            example02Data()
            example03Chunks()
            example04Files()
            example05Pointers()
            example06Scratchpads()
            example07Graph()
            example08Registers()
            example09Vaults()
            example10PrivateData()
        }
        else -> println("Unknown example: $example. Use 1-10 or 'all'.")
    }
}

private fun randomHex(bytes: Int = 32): String {
    val data = ByteArray(bytes)
    SecureRandom().nextBytes(data)
    return data.joinToString("") { "%02x".format(it) }
}

/** Example 01: Connect to antd daemon and check health. */
suspend fun example01Connect() {
    println("=== Example 01: Connect ===")
    val client = AntdClient.createRest()

    val status = client.health()
    println("Daemon healthy: ${status.ok}")
    println("Network: ${status.network}")

    if (!status.ok) throw RuntimeException("antd daemon is not healthy")

    println("Connection OK!\n")
    client.close()
}

/** Example 02: Store and retrieve public data, with cost estimation. */
suspend fun example02Data() {
    println("=== Example 02: Public Data ===")
    val client = AntdClient.createRest()

    val payload = "Hello, Autonomi network!".toByteArray()

    // Estimate cost
    val cost = client.dataCost(payload)
    println("Estimated cost: $cost atto tokens")

    // Store public data
    val result = client.dataPutPublic(payload)
    println("Stored at address: ${result.address}")
    println("Actual cost: ${result.cost} atto tokens")

    // Retrieve
    val data = client.dataGetPublic(result.address)
    val text = String(data)
    println("Retrieved: $text")

    check(data.contentEquals(payload)) { "Round-trip mismatch!" }

    println("Public data round-trip OK!\n")
    client.close()
}

/** Example 03: Store and retrieve raw chunks. */
suspend fun example03Chunks() {
    println("=== Example 03: Chunks ===")
    val client = AntdClient.createRest()

    val rawData = "Raw chunk content for direct storage".toByteArray()

    val result = client.chunkPut(rawData)
    println("Chunk stored at: ${result.address}")
    println("Cost: ${result.cost} atto tokens")

    val retrieved = client.chunkGet(result.address)
    println("Retrieved ${retrieved.size} bytes")

    check(retrieved.contentEquals(rawData)) { "Chunk round-trip mismatch!" }

    println("Chunk round-trip OK!\n")
    client.close()
}

/** Example 04: Upload and download files. */
suspend fun example04Files() {
    println("=== Example 04: Files ===")
    val client = AntdClient.createRest()

    val srcFile = File.createTempFile("antd-example", ".txt")
    srcFile.writeText("Hello from a file on Autonomi!")

    try {
        // Estimate cost
        val cost = client.fileCost(srcFile.absolutePath)
        println("File upload cost estimate: $cost atto tokens")

        // Upload
        val result = client.fileUploadPublic(srcFile.absolutePath)
        println("File uploaded to: ${result.address}")
        println("Actual cost: ${result.cost} atto tokens")

        // Download to new location
        val destPath = srcFile.absolutePath + ".downloaded"
        client.fileDownloadPublic(result.address, destPath)
        println("Downloaded to: $destPath")

        val content = File(destPath).readText()
        println("Content: $content")
        File(destPath).delete()
    } finally {
        srcFile.delete()
    }

    println("File upload/download OK!\n")
    client.close()
}

/** Example 05: Create, read, and update mutable pointers. */
suspend fun example05Pointers() {
    println("=== Example 05: Pointers ===")
    val client = AntdClient.createRest()

    val secretKey = randomHex()

    // Store data to point to
    val dataV1 = client.dataPutPublic("version 1".toByteArray())
    val dataV2 = client.dataPutPublic("version 2".toByteArray())

    // Create pointer to v1
    val targetV1 = PointerTarget("chunk", dataV1.address)
    val ptr = client.pointerCreate(secretKey, targetV1)
    println("Pointer created at: ${ptr.address}")

    // Read
    val pointer = client.pointerGet(ptr.address)
    println("Points to: ${pointer.target.kind} @ ${pointer.target.address}")
    println("Counter: ${pointer.counter}")

    // Check existence
    val exists = client.pointerExists(ptr.address)
    println("Pointer exists: $exists")

    // Update to v2
    val targetV2 = PointerTarget("chunk", dataV2.address)
    client.pointerUpdate(secretKey, targetV2)
    println("Pointer updated to v2")

    // Read again
    val updated = client.pointerGet(ptr.address)
    println("Now points to: ${updated.target.address}")

    println("Pointer CRUD OK!\n")
    client.close()
}

/** Example 06: Create, read, and update versioned scratchpads. */
suspend fun example06Scratchpads() {
    println("=== Example 06: Scratchpads ===")
    val client = AntdClient.createRest()

    val secretKey = randomHex()

    // Create
    val initialData = "scratchpad v1 data".toByteArray()
    val contentType = 1UL
    val result = client.scratchpadCreate(secretKey, contentType, initialData)
    println("Scratchpad created at: ${result.address}")
    println("Cost: ${result.cost} atto tokens")

    // Read
    var pad = client.scratchpadGet(result.address)
    println("Data encoding: ${pad.dataEncoding}")
    println("Counter: ${pad.counter}")
    println("Data length: ${pad.data.size} bytes")

    // Check existence
    val exists = client.scratchpadExists(result.address)
    println("Scratchpad exists: $exists")

    // Update
    val updatedData = "scratchpad v2 data".toByteArray()
    client.scratchpadUpdate(secretKey, contentType, updatedData)
    println("Scratchpad updated")

    // Read again
    pad = client.scratchpadGet(result.address)
    println("Counter after update: ${pad.counter}")

    println("Scratchpad CRUD OK!\n")
    client.close()
}

/** Example 07: Graph entry (DAG node) operations. */
suspend fun example07Graph() {
    println("=== Example 07: Graph ===")
    val client = AntdClient.createRest()

    val secretKey = randomHex()

    // Create a root graph entry
    val content = randomHex()
    val result = client.graphEntryPut(
        secretKey,
        emptyList(),
        content,
        emptyList(),
    )
    println("Graph entry created at: ${result.address}")
    println("Cost: ${result.cost} atto tokens")

    // Read
    val entry = client.graphEntryGet(result.address)
    println("Owner: ${entry.owner}")
    println("Content: ${entry.content}")
    println("Parents: ${entry.parents.size}")
    println("Descendants: ${entry.descendants.size}")

    // Check existence
    val exists = client.graphEntryExists(result.address)
    println("Graph entry exists: $exists")

    // Estimate cost
    val cost = client.graphEntryCost(secretKey)
    println("Cost estimate for new entry: $cost atto tokens")

    println("Graph entry operations OK!\n")
    client.close()
}

/** Example 08: Register create, read, and update. */
suspend fun example08Registers() {
    println("=== Example 08: Registers ===")
    val client = AntdClient.createRest()

    val secretKey = randomHex()

    // Create with initial value (32 zero bytes)
    val initialValue = "0".repeat(64)
    val result = client.registerCreate(secretKey, initialValue)
    println("Register created at: ${result.address}")
    println("Cost: ${result.cost} atto tokens")

    // Read
    var reg = client.registerGet(result.address)
    println("Current value: ${reg.value}")

    // Update
    val newValue = randomHex()
    val updateResult = client.registerUpdate(secretKey, newValue)
    println("Update cost: ${updateResult.cost} atto tokens")

    // Read again
    reg = client.registerGet(result.address)
    println("Updated value: ${reg.value}")

    println("Register CRUD OK!\n")
    client.close()
}

/** Example 09: Vault store and retrieve. */
suspend fun example09Vaults() {
    println("=== Example 09: Vaults ===")
    val client = AntdClient.createRest()

    val secretKey = randomHex()

    // Store
    val payload = "Secret vault data that is encrypted".toByteArray()
    val contentType = 42UL
    val cost = client.vaultPut(secretKey, payload, contentType)
    println("Vault store cost: $cost atto tokens")

    // Retrieve
    val vault = client.vaultGet(secretKey)
    println("Content type: ${vault.contentType}")
    println("Data: ${String(vault.data)}")

    check(vault.data.contentEquals(payload)) { "Vault round-trip mismatch!" }
    check(vault.contentType == contentType) { "Content type mismatch!" }

    println("Vault round-trip OK!\n")
    client.close()
}

/** Example 10: Private (encrypted) data round-trip. */
suspend fun example10PrivateData() {
    println("=== Example 10: Private Data ===")
    val client = AntdClient.createRest()

    val secretMessage = "This message is encrypted on the network".toByteArray()

    // Store private data
    val result = client.dataPutPrivate(secretMessage)
    val dataMap = result.address
    println("Data map: $dataMap")
    println("Cost: ${result.cost} atto tokens")

    // Retrieve and decrypt
    val retrieved = client.dataGetPrivate(dataMap)
    println("Decrypted: ${String(retrieved)}")

    check(retrieved.contentEquals(secretMessage)) { "Private data round-trip mismatch!" }

    println("Private data round-trip OK!\n")
    client.close()
}
