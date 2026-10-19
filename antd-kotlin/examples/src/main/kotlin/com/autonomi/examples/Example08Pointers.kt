package com.autonomi.examples

import com.autonomi.sdk.AlreadyExistsException
import com.autonomi.sdk.AntdClient

/**
 * Example 08: Pointers. Points a mutable, owner-signed reference at one piece
 * of public data, moves it to another, reads it back and asks the close group
 * where it stands.
 *
 * Needs a daemon holding the owner key (`antd --pointer-keys <file-or-dir>`)
 * and a wallet: every pointer write pays, about the price of one chunk, and
 * every attempt pays again, so nothing here is retried. Set
 * `ANTD_POINTER_OWNER` to a pointer address the daemon holds the key for
 * (`pointerKeys()` lists them) that has never been written: the create below
 * fails on a pointer that exists. `ANTD_BASE_URL` overrides the daemon URL.
 *
 * Not part of `all`; run it explicitly:
 *
 * ```bash
 * ANTD_POINTER_OWNER=<hex> ./gradlew :examples:run --args="8"
 * ```
 */
suspend fun example08Pointers() {
    println("=== Example 08: Pointers ===")
    val owner = System.getenv("ANTD_POINTER_OWNER")?.trim()?.lowercase()?.removePrefix("0x").orEmpty()
    if (owner.isEmpty()) {
        println("Skipped: set ANTD_POINTER_OWNER to a never-written pointer address the daemon holds the key for.\n")
        return
    }
    val baseUrl = System.getenv("ANTD_BASE_URL")?.trim()?.takeIf { it.isNotEmpty() } ?: "http://localhost:8082"
    val client = AntdClient.createRest(baseUrl)

    try {
        // The daemon signs with the owner's key, so it must hold it. It
        // returns bare lowercase hex.
        val keys = client.pointerKeys()
        check(owner in keys) { "antd at $baseUrl holds no key for $owner; it holds $keys" }

        // 1. Two small pieces of public data to point at.
        val first = client.dataPutPublic("Pointer target, version 1".toByteArray()).address
        val second = client.dataPutPublic("Pointer target, version 2".toByteArray()).address
        println("Stored version 1 at $first")
        println("Stored version 2 at $second")

        // 2. Create the pointer at the first. Paid; a pointer that already
        //    exists is refused before anything is paid.
        val created = try {
            client.pointerCreate(owner, first)
        } catch (e: AlreadyExistsException) {
            throw IllegalStateException("pointer $owner already exists; use a never-written owner", e)
        }
        println("Created pointer ${created.address} -> $first (counter ${created.counter})")

        // 3. Move it to the second. Paid again; the counter goes up by one.
        val updated = client.pointerUpdate(owner, second)
        println("Updated pointer -> $second (counter ${updated.counter})")

        // 4. Read it back, and follow it to the data.
        val record = client.pointerGet(owner)
        println("Pointer record: counter ${record.counter}, ${record.kind} target ${record.target}, final ${record.isFinal}")
        val resolved = client.pointerResolve(owner)
        check(resolved.target == second) { "pointer resolved to ${resolved.target}, expected $second" }
        println("Resolves to: ${String(client.dataGetPublic(resolved.target))}")

        // 5. Ask the whole close group where it stands. "open" means the owner
        //    can still move it; only "final" means it is handed over for good.
        val finality = client.pointerFinality(owner)
        println(
            "Finality: ${finality.status.wire} (${finality.answered}/${finality.group} peers answered, " +
                "counter ${finality.counter ?: "none"})",
        )
    } finally {
        client.close()
    }

    println("Pointer round-trip OK!\n")
}
