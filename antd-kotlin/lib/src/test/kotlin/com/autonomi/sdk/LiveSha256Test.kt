package com.autonomi.sdk

import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assumptions.assumeTrue
import java.security.MessageDigest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Live `sha256` checks (antd 0.17.0 or later) against a running antd with a
 * network behind it. Everything is free except one small public data upload
 * per transport.
 *
 * Skipped unless both are set:
 *
 * - `ANTD_TEST_URL`: the daemon's REST base URL, e.g. `http://127.0.0.1:8082`
 * - `ANTD_TEST_SHA_LINK`: a manifest link with entries `public.txt` and
 *   `private.txt` (each with a sha256) and `nohash.txt` (none)
 *
 * Used when set:
 *
 * - `ANTD_TEST_SHA_PUBLIC_ADDRESS` / `ANTD_TEST_SHA_PUBLIC_SHA256`: a public
 *   upload and its plaintext's SHA-256 (the manifest build checks need both)
 * - `ANTD_TEST_SHA_DATA_MAP_SHA256`: the private entry's SHA-256
 * - `ANTD_TEST_GRPC`: the daemon's gRPC target, e.g. `127.0.0.1:50051`, to
 *   repeat the checks over gRPC
 *
 * ```text
 * ANTD_TEST_URL=http://127.0.0.1:8082 ANTD_TEST_SHA_LINK=ant://manifest/... \
 *   ./gradlew :lib:test --tests '*LiveSha256Test*'
 * ```
 */
class LiveSha256Test {

    private fun env(name: String): String? = System.getenv(name)?.trim()?.takeIf { it.isNotEmpty() }

    private fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private suspend fun check(label: String, c: IAntdClient, link: String) {
        val publicAddress = env("ANTD_TEST_SHA_PUBLIC_ADDRESS")
        val publicSha = env("ANTD_TEST_SHA_PUBLIC_SHA256")
        val dataMapSha = env("ANTD_TEST_SHA_DATA_MAP_SHA256")

        // 1. The fixture link's entries carry (or lack) their hashes.
        val decoded = c.decodeManifestLink(link, resolve = false)
        val byName = decoded.entries.associateBy { it.effectiveName }
        if (publicSha != null) assertEquals(publicSha, byName.getValue("public.txt").sha256, "$label public.txt")
        if (dataMapSha != null) assertEquals(dataMapSha, byName.getValue("private.txt").sha256, "$label private.txt")
        assertNull(byName.getValue("nohash.txt").sha256, "$label nohash.txt has no hash")

        // 2. A build carries a given hash back on the entry; 3. a bad one is a bad request.
        if (publicAddress != null && publicSha != null) {
            val built = c.buildManifest(listOf(ManifestEntryInput(path = "a.txt", address = publicAddress, sha256 = publicSha)))
            assertEquals(publicSha, built.entries.single().sha256, "$label build")
            assertEquals(publicSha, c.decodeManifest(built.manifest).entries.single().sha256, "$label decode of the build")
            val none = c.buildManifest(listOf(ManifestEntryInput(path = "a.txt", address = publicAddress)))
            assertNull(none.entries.single().sha256, "$label an unset hash stays unset")
        }
        if (publicAddress != null) {
            val bad = assertFailsWith<BadRequestException>("$label bad sha256") {
                c.buildManifest(listOf(ManifestEntryInput(path = "a.txt", address = publicAddress, sha256 = "zz")))
            }
            assertEquals(400, bad.statusCode)
            assertTrue(bad.message!!.contains("sha256"), bad.message)
        }

        // 4. The one paid call: a small public upload reports its plaintext's hash.
        val payload = "sha-fanout kotlin ${System.currentTimeMillis() / 1000} $label".toByteArray(Charsets.UTF_8)
        val expected = sha256Hex(payload)
        val put = c.dataPutPublic(payload)
        println("LiveSha256Test $label: uploaded ${payload.size} bytes, local sha256=$expected, returned sha256=${put.sha256}")
        assertEquals(expected, put.sha256, "$label dataPutPublic sha256")
    }

    @Test
    fun `live sha256 on manifests and uploads`() = runBlocking<Unit> {
        val restUrl = env("ANTD_TEST_URL")
        val link = env("ANTD_TEST_SHA_LINK")
        assumeTrue(restUrl != null && link != null, "set ANTD_TEST_URL and ANTD_TEST_SHA_LINK to run")
        val grpcTarget = env("ANTD_TEST_GRPC")?.removePrefix("http://")

        AntdRestClient(restUrl!!).use { check("rest", it, link!!) }
        if (grpcTarget != null) AntdGrpcClient(grpcTarget).use { check("grpc", it, link!!) }
    }
}
