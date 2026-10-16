package com.autonomi.examples

import com.autonomi.sdk.AntdClient
import com.autonomi.sdk.BuildManifestOptions
import com.autonomi.sdk.ManifestEntryInput

/**
 * Example 09: Manifests. Uploads two small pieces of public data, builds a
 * `.ant` manifest that names them `notes/one.txt` and `notes/two.txt`, and
 * decodes its `ant://` link, asking the daemon for each entry's exact size.
 *
 * Building and decoding a manifest are free: nothing is uploaded or paid for.
 * The two uploads pay, so the daemon needs a wallet. Needs the antd release
 * after 0.15.0. `ANTD_BASE_URL` overrides the daemon URL (default
 * `http://localhost:8082`).
 *
 * Not part of `all`; run it explicitly:
 *
 * ```bash
 * ./gradlew :examples:run --args="9"
 * ```
 */
suspend fun example09Manifests() {
    println("=== Example 09: Manifests ===")
    val baseUrl = System.getenv("ANTD_BASE_URL")?.trim()?.takeIf { it.isNotEmpty() } ?: "http://localhost:8082"
    val client = AntdClient.createRest(baseUrl)

    try {
        // 1. Two small pieces of public data. Each upload pays.
        val notes = mapOf(
            "notes/one.txt" to "The first note in the manifest example.".toByteArray(),
            "notes/two.txt" to "The second note, a little longer than the first.".toByteArray(),
        )
        val addresses = notes.mapValues { (path, bytes) ->
            client.dataPutPublic(bytes).address.also { println("Stored $path (${bytes.size} bytes) at $it") }
        }

        // 2. Build a manifest of them. Free: it only describes what is stored.
        val built = client.buildManifest(
            addresses.map { (path, address) -> ManifestEntryInput(address = address, path = path) },
            BuildManifestOptions(name = "example"),
        )
        println("Manifest: ${built.manifest.size} bytes")
        println("Link: ${built.link ?: "(none: too long for a link; share the .ant bytes instead)"}")
        built.entries.forEach { println("  ${it.effectiveName} -> ${it.contentAddress}") }

        // 3. Decode the link, resolving each entry's exact size. Also free.
        val decoded = built.link?.let { client.decodeManifestLink(it, resolve = true) }
            ?: client.decodeManifest(built.manifest, resolve = true)
        println("Decoded \"${decoded.name}\" (${decoded.source}), ${decoded.entries.size} entries:")
        decoded.entries.forEach { e ->
            println("  ${e.effectiveName}: exact size ${e.exactSize ?: "unknown (${e.error})"}")
            val expected = notes.getValue(e.effectiveName).size.toULong()
            check(e.exactSize == expected) { "${e.effectiveName}: exact size ${e.exactSize}, expected $expected" }
        }
    } finally {
        client.close()
    }

    println("Manifest round-trip OK!\n")
}
