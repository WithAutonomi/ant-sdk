package com.autonomi.sdk

import antd.v1.*
import com.google.protobuf.ByteString
import io.grpc.Grpc
import io.grpc.InsecureServerCredentials
import io.grpc.ManagedChannel
import io.grpc.Server
import io.grpc.Status
import io.grpc.StatusException
import io.grpc.inprocess.InProcessChannelBuilder
import io.grpc.inprocess.InProcessServerBuilder
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The gRPC manifest surface against an in-process ManifestService: raw
 * `bytes` both ways, proto3 `optional` presence (an unset size reads as null,
 * never 0), the both-or-neither entry check, `embed_roots` always sent and
 * true by default, INVALID_ARGUMENT mapping to [BadRequestException], and the
 * raised message limits, over a real loopback connection.
 */
class ManifestGrpcTest {

    private lateinit var server: Server
    private lateinit var channel: ManagedChannel
    private lateinit var client: AntdGrpcClient
    private lateinit var manifests: MockManifestService

    companion object {
        /** The five-byte `.ant` header. */
        val HEADER = byteArrayOf(0xC1.toByte(), 'A'.code.toByte(), 'N'.code.toByte(), 'T'.code.toByte(), 0x01)
        const val LINK = "ant://manifest/wUFOVAE"
        val ADDR = "11".repeat(32)
        val CA = "cc".repeat(32)

        /** Past grpc-java's 4 MiB default receive limit, well under the raised one. */
        const val BIG = 5 * 1024 * 1024
    }

    /** Answers from fields a test sets; records the last request of each kind. */
    class MockManifestService : ManifestServiceGrpcKt.ManifestServiceCoroutineImplBase() {
        var failWith: StatusException? = null
        var buildResponse: Manifests.BuildManifestResponse = buildManifestResponse {}
        var decodeResponse: Manifests.DecodeManifestResponse = decodeManifestResponse {}
        var calls = 0
        var lastBuild: Manifests.BuildManifestRequest? = null
        var lastDecode: Manifests.DecodeManifestRequest? = null

        override suspend fun build(request: Manifests.BuildManifestRequest): Manifests.BuildManifestResponse {
            calls++
            lastBuild = request
            failWith?.let { throw it }
            return buildResponse
        }

        override suspend fun decode(request: Manifests.DecodeManifestRequest): Manifests.DecodeManifestResponse {
            calls++
            lastDecode = request
            failWith?.let { throw it }
            return decodeResponse
        }
    }

    @BeforeTest
    fun setUp() {
        val name = InProcessServerBuilder.generateName()
        manifests = MockManifestService()
        server = InProcessServerBuilder.forName(name).directExecutor().addService(manifests).build().start()
        channel = InProcessChannelBuilder.forName(name).directExecutor().build()
        client = AntdGrpcClient(channel)
    }

    @AfterTest
    fun tearDown() {
        client.close()
        channel.shutdownNow()
        server.shutdownNow()
    }

    // ── buildManifest ──

    @Test
    fun `buildManifest sends both entry kinds with presence, and returns the raw bytes`() = runTest {
        manifests.buildResponse = buildManifestResponse {
            manifest = ByteString.copyFrom(HEADER)
            link = LINK
            entries += manifestEntryInfo {
                effectiveName = "a.txt"
                path = "a.txt"
                size = 10
                kind = "embedded"
                contentAddress = CA
                exactSize = 10
            }
            entries += manifestEntryInfo {
                effectiveName = ADDR
                kind = "public"
                contentAddress = ADDR
            }
        }
        val built = client.buildManifest(
            listOf(
                ManifestEntryInput(path = "a.txt", size = 10u, dataMap = "abcd"),
                ManifestEntryInput(address = ADDR),
            ),
            BuildManifestOptions(name = "album", torrentInfoHashes = listOf("aa".repeat(20))),
        )

        val req = manifests.lastBuild!!
        assertTrue(req.hasName())
        assertEquals("album", req.name)
        assertEquals(listOf("aa".repeat(20)), req.torrentInfoHashesList)
        assertTrue(req.hasEmbedRoots() && req.embedRoots, "embed_roots must be sent, and true by default")
        val (first, second) = req.entriesList
        assertTrue(first.hasPath() && first.hasSize())
        assertEquals("a.txt", first.path)
        assertEquals(10L, first.size)
        assertEquals(Manifests.ManifestEntryInput.SourceCase.DATA_MAP, first.sourceCase)
        assertEquals("abcd", first.dataMap)
        assertFalse(second.hasPath() || second.hasSize(), "unset path and size must be absent, not empty or 0")
        assertEquals(Manifests.ManifestEntryInput.SourceCase.ADDRESS, second.sourceCase)
        assertEquals(ADDR, second.address)

        assertContentEquals(HEADER, built.manifest)
        assertEquals(LINK, built.link)
        val (a, p) = built.entries
        assertEquals(ManifestEntryInfo("a.txt", "embedded", CA, path = "a.txt", size = 10uL, exactSize = 10uL), a)
        // Absent optionals and empty strings read as null.
        assertEquals(ManifestEntryInfo(ADDR, "public", ADDR), p)
    }

    @Test
    fun `buildManifest sends embed_roots false when asked, and omits an empty name`() = runTest {
        client.buildManifest(listOf(ManifestEntryInput(address = ADDR, path = "")), BuildManifestOptions(name = "", embedRoots = false))
        val req = manifests.lastBuild!!
        assertTrue(req.hasEmbedRoots(), "embed_roots must always be sent")
        assertFalse(req.embedRoots)
        assertFalse(req.hasName())
        assertFalse(req.entriesList.single().hasPath())
        assertTrue(req.torrentInfoHashesList.isEmpty())
    }

    @Test
    fun `buildManifest with no link and no sizes reads them as null`() = runTest {
        manifests.buildResponse = buildManifestResponse {
            manifest = ByteString.copyFrom(HEADER)
            entries += manifestEntryInfo {
                effectiveName = "p"
                path = "p"
                kind = "public"
                contentAddress = ADDR
            }
        }
        val built = client.buildManifest(listOf(ManifestEntryInput(path = "p", address = ADDR)))
        assertNull(built.link, "an empty link means it did not fit")
        assertNull(built.entries.single().size)
        assertNull(built.entries.single().exactSize)
    }

    @Test
    fun `sizes keep all 64 bits, and a set 0 stays 0`() = runTest {
        manifests.buildResponse = buildManifestResponse {
            entries += manifestEntryInfo {
                effectiveName = "big"
                kind = "public"
                contentAddress = ADDR
                size = -1L // u64::MAX on the wire
                exactSize = 0
            }
        }
        val built = client.buildManifest(listOf(ManifestEntryInput(size = ULong.MAX_VALUE, address = ADDR)))
        assertEquals(-1L, manifests.lastBuild!!.entriesList.single().size)
        assertEquals(ULong.MAX_VALUE, built.entries.single().size)
        assertEquals(0uL, built.entries.single().exactSize)
    }

    @Test
    fun `buildManifest rejects an entry with both or neither source before sending`() = runTest {
        for (bad in listOf(ManifestEntryInput(path = "x"), ManifestEntryInput(dataMap = "aa", address = ADDR))) {
            val ex = assertFailsWith<BadRequestException>("$bad") { client.buildManifest(listOf(bad)) }
            assertEquals(400, ex.statusCode)
            val reason = if (bad.dataMap == null) "needs a data_map or an address" else "give data_map or address, not both"
            assertEquals("1 invalid entries: entries[0]: $reason", ex.message)
        }
        assertEquals(0, manifests.calls, "nothing may be sent")
    }

    @Test
    fun `INVALID_ARGUMENT naming the entry is a BadRequestException carrying the daemon's message`() = runTest {
        manifests.failWith = Status.INVALID_ARGUMENT
            .withDescription("Bad request: entries[0]: invalid path \"../x\": parent components are not allowed")
            .asException()
        val ex = assertFailsWith<BadRequestException> {
            client.buildManifest(listOf(ManifestEntryInput(address = ADDR, path = "../x")))
        }
        assertTrue(ex.message!!.contains("entries[0]: invalid path"), ex.message)
        assertFailsWith<BadRequestException> { client.decodeManifest("nope".toByteArray()) }
    }

    // ── decodeManifest / decodeManifestLink ──

    @Test
    fun `decodeManifest sends the raw bytes and maps every field`() = runTest {
        manifests.decodeResponse = decodeManifestResponse {
            source = "manifest"
            name = "album"
            torrentInfoHashV2 = "bb".repeat(32)
            entries += manifestEntryInfo {
                effectiveName = "a.txt"
                path = "a.txt"
                kind = "embedded"
                contentAddress = CA
                dataMap = "abcd"
                exactSize = 3
            }
            entries += manifestEntryInfo {
                effectiveName = "b"
                path = "b"
                kind = "public"
                contentAddress = ADDR
                error = "Record not found: gone"
            }
        }
        val decoded = client.decodeManifest(HEADER, resolve = true)

        val req = manifests.lastDecode!!
        assertEquals(Manifests.DecodeManifestRequest.InputCase.MANIFEST, req.inputCase)
        assertContentEquals(HEADER, req.manifest.toByteArray())
        assertTrue(req.resolve)

        assertEquals("manifest", decoded.source)
        assertEquals("album", decoded.name)
        assertNull(decoded.torrentInfoHashV1, "an empty hash reads as null")
        assertEquals("bb".repeat(32), decoded.torrentInfoHashV2)
        val (a, b) = decoded.entries
        assertEquals("abcd", a.dataMap)
        assertEquals(3uL, a.exactSize)
        assertNull(a.size)
        assertNull(a.error)
        assertEquals("Record not found: gone", b.error)
        assertNull(b.exactSize)
        assertNull(b.dataMap)
    }

    @Test
    fun `decodeManifestLink sends the link, resolve defaulting to false`() = runTest {
        manifests.decodeResponse = decodeManifestResponse {
            source = "file_link"
            entries += manifestEntryInfo {
                effectiveName = ADDR
                kind = "public"
                contentAddress = ADDR
            }
        }
        val decoded = client.decodeManifestLink(ADDR)
        val req = manifests.lastDecode!!
        assertEquals(Manifests.DecodeManifestRequest.InputCase.LINK, req.inputCase)
        assertEquals(ADDR, req.link)
        assertFalse(req.resolve)
        assertEquals(DecodedManifest("file_link", null, null, null, listOf(ManifestEntryInfo(ADDR, "public", ADDR))), decoded)
    }

    @Test
    fun `decode rejects empty input before sending`() = runTest {
        for (call in listOf<suspend () -> Any>({ client.decodeManifest(ByteArray(0)) }, { client.decodeManifestLink("") })) {
            val ex = assertFailsWith<BadRequestException> { call() }
            assertEquals(400, ex.statusCode)
            assertEquals("needs a manifest (base64 .ant bytes) or a link", ex.message)
        }
        assertEquals(0, manifests.calls, "nothing may be sent")
    }

    // ── Message limits ──

    @Test
    fun `the manifest stub raises both message limits`() {
        val options = client.manifestStub.callOptions
        assertEquals(MAX_MANIFEST_GRPC_MESSAGE, options.maxInboundMessageSize)
        assertEquals(MAX_MANIFEST_GRPC_MESSAGE, options.maxOutboundMessageSize)
        assertEquals(256 * 1024 * 1024, MAX_MANIFEST_GRPC_MESSAGE)
    }

    /**
     * Over a real loopback HTTP/2 connection, where the limits are enforced
     * (the in-process transport does not serialize): a 5 MiB manifest goes
     * out in a Decode and comes back in a Build and a Decode, past the 4 MiB
     * a default stub accepts, which the control call shows.
     */
    @Test
    fun `a manifest past the default 4 MiB limit goes both ways over a real connection`() = runBlocking<Unit> {
        val big = ByteArray(BIG) { (it % 251).toByte() }
        val service = object : ManifestServiceGrpcKt.ManifestServiceCoroutineImplBase() {
            override suspend fun build(request: Manifests.BuildManifestRequest) =
                buildManifestResponse { manifest = ByteString.copyFrom(big) }

            override suspend fun decode(request: Manifests.DecodeManifestRequest) = decodeManifestResponse {
                source = "manifest"
                // Echo the size of what arrived, in a response that is itself past 4 MiB.
                name = request.manifest.size().toString()
                entries += manifestEntryInfo { dataMap = "ab".repeat(BIG / 2) }
            }
        }
        // The daemon accepts manifest requests up to 100 MiB; so does this server.
        val tcp = Grpc.newServerBuilderForPort(0, InsecureServerCredentials.create())
            .maxInboundMessageSize(100 * 1024 * 1024)
            .addService(service)
            .build()
            .start()
        val target = "127.0.0.1:${tcp.port}"
        val real = AntdGrpcClient(target)
        val control = io.grpc.ManagedChannelBuilder.forTarget(target).usePlaintext().build()
        try {
            assertContentEquals(big, real.buildManifest(listOf(ManifestEntryInput(address = ADDR))).manifest)

            val decoded = real.decodeManifest(big)
            assertEquals(BIG.toString(), decoded.name, "the whole manifest must arrive")
            assertEquals(BIG, decoded.entries.single().dataMap!!.length)

            // Control: the same call on a stub with grpc-java's defaults fails.
            val ex = assertFailsWith<StatusException> {
                ManifestServiceGrpcKt.ManifestServiceCoroutineStub(control).build(buildManifestRequest {})
            }
            assertEquals(Status.Code.RESOURCE_EXHAUSTED, ex.status.code)
        } finally {
            real.close()
            control.shutdownNow()
            tcp.shutdownNow()
        }
    }
}
