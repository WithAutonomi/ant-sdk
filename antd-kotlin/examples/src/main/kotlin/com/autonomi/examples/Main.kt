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
        "6" -> example06PrivateData()
        "7" -> example07ExternalSigner()
        "all" -> {
            example01Connect()
            example02Data()
            example03Chunks()
            example04Files()
            example06PrivateData()
            example07ExternalSigner()
        }
        else -> println("Unknown example: $example. Use 1-7 or 'all'.")
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
    val est = client.dataCost(payload)
    println("Estimate: ${est.fileSize} bytes in ${est.chunkCount} chunks, storage ${est.cost} atto, gas ${est.estimatedGasCostWei} wei, mode ${est.paymentMode}")

    // Store public data
    val result = client.dataPutPublic(payload)
    println("Stored at address: ${result.address}")
    println("Chunks stored: ${result.chunksStored}, payment mode: ${result.paymentModeUsed}")

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
        val est = client.fileCost(srcFile.absolutePath)
        println("Estimate: ${est.fileSize} bytes in ${est.chunkCount} chunks, storage ${est.cost} atto, gas ${est.estimatedGasCostWei} wei, mode ${est.paymentMode}")

        // Upload publicly
        val result = client.filePutPublic(srcFile.absolutePath)
        println("File uploaded to: ${result.address}")
        println("Storage cost: ${result.storageCostAtto} atto, gas: ${result.gasCostWei} wei")
        println("Chunks stored: ${result.chunksStored}, payment mode: ${result.paymentModeUsed}")

        // Download to new location
        val destPath = srcFile.absolutePath + ".downloaded"
        client.fileGetPublic(result.address, destPath)
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

/** Example 06: Private (encrypted) data round-trip. */
suspend fun example06PrivateData() {
    println("=== Example 06: Private Data ===")
    val client = AntdClient.createRest()

    val secretMessage = "This message is encrypted on the network".toByteArray()

    // Store private data — DataMap is returned to the caller; NOT stored on-network.
    val result = client.dataPut(secretMessage)
    println("Data map: ${result.dataMap}")
    println("Chunks stored: ${result.chunksStored}, payment mode: ${result.paymentModeUsed}")

    // Retrieve and decrypt
    val retrieved = client.dataGet(result.dataMap)
    println("Decrypted: ${String(retrieved)}")

    check(retrieved.contentEquals(secretMessage)) { "Private data round-trip mismatch!" }

    println("Private data round-trip OK!\n")
    client.close()
}
