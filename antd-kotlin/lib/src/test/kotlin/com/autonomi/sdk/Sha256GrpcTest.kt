package com.autonomi.sdk

import antd.v1.*
import io.grpc.ManagedChannel
import io.grpc.Server
import io.grpc.Status
import io.grpc.StatusException
import io.grpc.inprocess.InProcessChannelBuilder
import io.grpc.inprocess.InProcessServerBuilder
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * The `sha256` fields antd 0.17.0 added, over gRPC against in-process
 * services: every upload result reads it, with "" (proto3's zero value) as
 * null; a manifest entry input sets it only when given and non-empty
 * (proto3 `optional` presence); a manifest entry info reads it, "" as null;
 * INVALID_ARGUMENT is a [BadRequestException].
 */
class Sha256GrpcTest {

    private lateinit var server: Server
    private lateinit var channel: ManagedChannel
    private lateinit var client: AntdGrpcClient

    /** The sha256 every upload service answers with; "" is the proto3 zero value. */
    private var sha: String = SHA
    private var buildResponse: Manifests.BuildManifestResponse = buildManifestResponse {}
    private var decodeResponse: Manifests.DecodeManifestResponse = decodeManifestResponse {}
    private var lastBuild: Manifests.BuildManifestRequest? = null
    private var buildFailure: StatusException? = null

    companion object {
        val SHA = "ab".repeat(32)
        val ADDR = "11".repeat(32)
        val CA = "cc".repeat(32)
    }

    private inner class MockData : DataServiceGrpcKt.DataServiceCoroutineImplBase() {
        override suspend fun put(request: Data.PutDataRequest) = putDataResponse {
            dataMap = "abcd"
            chunksStored = 3
            sha256 = sha
        }

        override suspend fun putPublic(request: Data.PutPublicDataRequest) = putPublicDataResponse {
            address = ADDR
            chunksStored = 3
            sha256 = sha
        }
    }

    private inner class MockFiles : FileServiceGrpcKt.FileServiceCoroutineImplBase() {
        override suspend fun put(request: Files.PutFileRequest) = putFileResponse {
            dataMap = "abcd"
            chunksStored = 3
            sha256 = sha
        }

        override suspend fun putPublic(request: Files.PutFileRequest) = putFilePublicResponse {
            address = ADDR
            chunksStored = 3
            sha256 = sha
        }
    }

    private inner class MockUpload : UploadServiceGrpcKt.UploadServiceCoroutineImplBase() {
        override suspend fun finalizeUpload(request: Upload.FinalizeUploadRequest) = finalizeUploadResponse {
            chunksStored = 4
            dataMap = "abcd"
            sha256 = sha
        }
    }

    private inner class MockManifest : ManifestServiceGrpcKt.ManifestServiceCoroutineImplBase() {
        override suspend fun build(request: Manifests.BuildManifestRequest): Manifests.BuildManifestResponse {
            lastBuild = request
            buildFailure?.let { throw it }
            return buildResponse
        }

        override suspend fun decode(request: Manifests.DecodeManifestRequest): Manifests.DecodeManifestResponse = decodeResponse
    }

    @BeforeTest
    fun setUp() {
        val name = InProcessServerBuilder.generateName()
        server = InProcessServerBuilder.forName(name).directExecutor()
            .addService(MockData()).addService(MockFiles()).addService(MockUpload()).addService(MockManifest())
            .build().start()
        channel = InProcessChannelBuilder.forName(name).directExecutor().build()
        client = AntdGrpcClient(channel)
    }

    @AfterTest
    fun tearDown() {
        client.close()
        channel.shutdownNow()
        server.shutdownNow()
    }

    private suspend fun results(): List<String?> = listOf(
        client.dataPut("x".toByteArray()).sha256,
        client.dataPutPublic("x".toByteArray()).sha256,
        client.filePut("/tmp/x").sha256,
        client.filePutPublic("/tmp/x").sha256,
        client.finalizeUpload("up-1", mapOf("q" to "t")).sha256,
        client.finalizeMerkleUpload("up-1", "0xwinner").sha256,
    )

    @Test
    fun `every upload result reads sha256`() = runTest {
        assertEquals(List(6) { SHA }, results())
    }

    @Test
    fun `every upload result reads an empty sha256 as null`() = runTest {
        sha = ""
        assertEquals(List(6) { null }, results())
    }

    @Test
    fun `buildManifest sets sha256 only on an entry that gives a non-empty one`() = runTest {
        client.buildManifest(
            listOf(
                ManifestEntryInput(path = "a.txt", address = ADDR, sha256 = SHA),
                ManifestEntryInput(path = "b.txt", address = ADDR),
                ManifestEntryInput(path = "c.txt", address = ADDR, sha256 = ""),
            ),
        )
        val (a, b, c) = lastBuild!!.entriesList
        assertTrue(a.hasSha256())
        assertEquals(SHA, a.sha256)
        assertFalse(b.hasSha256(), "unset sha256 must be absent")
        assertFalse(c.hasSha256(), "an empty sha256 must be absent, not set to an empty string")
    }

    @Test
    fun `buildManifest passes sha256 through exactly as given`() = runTest {
        client.buildManifest(listOf(ManifestEntryInput(address = ADDR, sha256 = "ZZ")))
        assertEquals("ZZ", lastBuild!!.entriesList.single().sha256)
    }

    @Test
    fun `build and decode read sha256 on entries, with an empty one as null`() = runTest {
        val infos = listOf(SHA, "").map { s ->
            manifestEntryInfo {
                effectiveName = "x"
                kind = "public"
                contentAddress = CA
                sha256 = s
            }
        }
        buildResponse = buildManifestResponse { entries += infos }
        decodeResponse = decodeManifestResponse {
            source = "manifest"
            entries += infos
        }
        assertEquals(listOf(SHA, null), client.buildManifest(listOf(ManifestEntryInput(address = ADDR))).entries.map { it.sha256 })
        assertEquals(listOf(SHA, null), client.decodeManifest(byteArrayOf(1)).entries.map { it.sha256 })
        assertEquals(listOf(SHA, null), client.decodeManifestLink("ant://manifest/wUFOVAE").entries.map { it.sha256 })
    }

    @Test
    fun `INVALID_ARGUMENT for a bad sha256 is a BadRequestException keeping the daemon's message`() = runTest {
        buildFailure = Status.INVALID_ARGUMENT.withDescription("entries[0]: sha256 must be 32 bytes, got 1").asException()
        val ex = assertFailsWith<BadRequestException> {
            client.buildManifest(listOf(ManifestEntryInput(address = ADDR, sha256 = "ab")))
        }
        assertEquals(400, ex.statusCode)
        assertTrue(ex.message!!.contains("entries[0]: sha256 must be 32 bytes, got 1"), ex.message)
    }
}
