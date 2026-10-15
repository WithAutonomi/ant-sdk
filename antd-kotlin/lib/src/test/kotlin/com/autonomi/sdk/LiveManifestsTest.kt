package com.autonomi.sdk

import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assumptions.assumeTrue
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Live manifest build and decode against a running antd with a network
 * behind it. It makes no paid calls: it only describes data already uploaded.
 *
 * Skipped unless both are set:
 *
 * - `ANTD_TEST_URL`: the daemon's REST base URL, e.g. `http://127.0.0.1:8082`
 * - `ANTD_TEST_MANIFEST_ADDRESSES`: two comma-separated addresses of public
 *   data uploads
 *
 * Used when set:
 *
 * - `ANTD_TEST_MANIFEST_SIZES`: the two uploads' exact plaintext sizes
 * - `ANTD_TEST_MANIFEST_DATA_MAP` / `ANTD_TEST_MANIFEST_DATA_MAP_SIZE`: a
 *   private upload's hex DataMap and its size
 * - `ANTD_TEST_MANIFEST_LINK`: an `ant://manifest/` link built from those
 *   three entries
 * - `ANTD_TEST_GRPC`: the daemon's gRPC target, e.g. `127.0.0.1:50051`, to
 *   repeat the checks over gRPC
 *
 * ```text
 * ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_MANIFEST_ADDRESSES=<hex>,<hex> \
 *   ./gradlew :lib:test --tests '*LiveManifestsTest*'
 * ```
 */
class LiveManifestsTest {

    private fun env(name: String): String? = System.getenv(name)?.trim()?.takeIf { it.isNotEmpty() }

    private fun list(name: String): List<String>? =
        env(name)?.split(',')?.map { it.trim().lowercase().removePrefix("0x") }?.filter { it.isNotEmpty() }

    @Test
    fun `live manifest build and decode`() = runBlocking<Unit> {
        val restUrl = env("ANTD_TEST_URL")
        val addresses = list("ANTD_TEST_MANIFEST_ADDRESSES")
        assumeTrue(
            restUrl != null && addresses != null && addresses.size == 2,
            "set ANTD_TEST_URL and ANTD_TEST_MANIFEST_ADDRESSES to run",
        )
        val (one, two) = addresses!!
        val sizes = list("ANTD_TEST_MANIFEST_SIZES")?.map { it.toULong() }
        val dataMap = env("ANTD_TEST_MANIFEST_DATA_MAP")
        val dataMapSize = env("ANTD_TEST_MANIFEST_DATA_MAP_SIZE")?.toULong()
        val fixtureLink = env("ANTD_TEST_MANIFEST_LINK")
        val grpcTarget = env("ANTD_TEST_GRPC")?.removePrefix("http://")

        // Two public entries, one with a recorded size, and the private one.
        val inputs = buildList {
            add(ManifestEntryInput(address = one, path = "public/one.txt"))
            add(ManifestEntryInput(address = two, path = "public/two.txt", size = 7u))
            if (dataMap != null) add(ManifestEntryInput(dataMap = dataMap, path = "private/three.txt"))
        }
        val options = BuildManifestOptions(name = "antd-kotlin-live")

        /** Checks a decode of the manifest built from [inputs]. */
        fun checkDecoded(d: DecodedManifest, resolved: Boolean) {
            assertEquals("manifest", d.source)
            assertEquals("antd-kotlin-live", d.name)
            assertNull(d.torrentInfoHashV1)
            assertNull(d.torrentInfoHashV2)
            val byName = d.entries.associateBy { it.effectiveName }
            assertEquals(inputs.map { it.path }.toSet(), byName.keys)
            val p1 = byName.getValue("public/one.txt")
            val p2 = byName.getValue("public/two.txt")
            assertEquals("public", p1.kind)
            assertEquals(one, p1.contentAddress)
            assertNull(p1.dataMap, "a public entry has no DataMap")
            assertNull(p1.size, "no recorded size must read as null, not 0")
            assertEquals(7uL, p2.size, "the recorded size is the creator's claim, as given")
            if (resolved) {
                assertNull(p1.error, p1.error)
                assertNull(p2.error, p2.error)
                if (sizes != null) {
                    assertEquals(sizes[0], p1.exactSize)
                    assertEquals(sizes[1], p2.exactSize)
                } else {
                    assertNotNull(p1.exactSize)
                }
            } else {
                assertNull(p1.exactSize, "a public entry's exact size is unknown until resolved")
            }
            if (dataMap != null) {
                val e = byName.getValue("private/three.txt")
                assertEquals("embedded", e.kind)
                assertTrue(!e.dataMap.isNullOrEmpty(), "an embedded entry decodes with its DataMap")
                if (resolved && dataMapSize != null) assertEquals(dataMapSize, e.exactSize)
            }
        }

        val rest = AntdRestClient(restUrl!!)
        val grpc = grpcTarget?.let { AntdGrpcClient(it) }
        try {
            // ── REST: build ──
            val built = rest.buildManifest(inputs, options)
            assertTrue(built.manifest.isNotEmpty())
            val link = assertNotNull(built.link, "a three-entry manifest fits a link")
            assertTrue(link.startsWith("ant://manifest/"), link)
            assertEquals(inputs.size, built.entries.size)
            assertEquals(built.entries.map { it.effectiveName }.sorted(), built.entries.map { it.effectiveName })
            val byName = built.entries.associateBy { it.effectiveName }
            assertEquals("public", byName.getValue("public/one.txt").kind)
            assertEquals(one, byName.getValue("public/one.txt").contentAddress)
            assertEquals("public", byName.getValue("public/two.txt").kind)
            assertEquals(two, byName.getValue("public/two.txt").contentAddress)
            assertNull(byName.getValue("public/one.txt").size)
            if (dataMap != null) assertEquals("embedded", byName.getValue("private/three.txt").kind)
            built.entries.forEach { assertNull(it.dataMap, "build reports no DataMaps: $it") }

            // ── REST: decode the bytes and the link ──
            checkDecoded(rest.decodeManifest(built.manifest), resolved = false)
            checkDecoded(rest.decodeManifest(built.manifest, resolve = true), resolved = true)
            checkDecoded(rest.decodeManifestLink(link, resolve = true), resolved = true)

            // ── The fixture link ──
            if (fixtureLink != null) {
                val f = rest.decodeManifestLink(fixtureLink, resolve = true)
                assertEquals("manifest", f.source)
                f.entries.forEach { assertNull(it.error, "${it.effectiveName}: ${it.error}") }
                assertTrue(f.entries.map { it.contentAddress }.containsAll(addresses), "${f.entries}")
                if (sizes != null && dataMapSize != null) {
                    assertEquals((sizes + dataMapSize).sorted(), f.entries.map { it.exactSize!! }.sorted())
                }
                if (dataMap != null) assertTrue(f.entries.any { it.kind == "embedded" && !it.dataMap.isNullOrEmpty() })
            }

            // ── Bad entries ──
            val bad = assertFailsWith<BadRequestException> {
                rest.buildManifest(listOf(ManifestEntryInput(address = one, path = "../x")))
            }
            assertTrue(bad.message!!.contains("entries[0]"), bad.message)
            assertFailsWith<IllegalArgumentException> {
                rest.buildManifest(listOf(ManifestEntryInput(address = one, dataMap = dataMap ?: "00")))
            }

            // ── gRPC: the same manifest, byte for byte ──
            if (grpc != null) {
                val g = grpc.buildManifest(inputs, options)
                assertContentEquals(built.manifest, g.manifest, "REST and gRPC must build the same bytes")
                assertEquals(built.link, g.link)
                assertEquals(built.entries, g.entries)
                checkDecoded(grpc.decodeManifest(g.manifest), resolved = false)
                checkDecoded(grpc.decodeManifest(g.manifest, resolve = true), resolved = true)
                checkDecoded(grpc.decodeManifestLink(g.link!!, resolve = true), resolved = true)
                if (fixtureLink != null) {
                    assertEquals(rest.decodeManifestLink(fixtureLink, resolve = true), grpc.decodeManifestLink(fixtureLink, resolve = true))
                }
                val gBad = assertFailsWith<BadRequestException> {
                    grpc.buildManifest(listOf(ManifestEntryInput(address = one, path = "../x")))
                }
                assertTrue(gBad.message!!.contains("entries[0]"), gBad.message)
            }
        } finally {
            rest.close()
            grpc?.close()
        }
    }
}
