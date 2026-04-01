package com.autonomi.sdk

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertIs

class SmokeTests {

    @Test
    fun `factory creates REST client`() {
        val client = AntdClient.createRest()
        assertIs<AntdRestClient>(client)
        client.close()
    }

    @Test
    fun `factory creates gRPC client`() {
        val client = AntdClient.createGrpc()
        assertIs<AntdGrpcClient>(client)
        client.close()
    }

    @Test
    fun `factory create with transport string`() {
        val rest = AntdClient.create("rest")
        assertIs<AntdRestClient>(rest)
        rest.close()

        val grpc = AntdClient.create("grpc")
        assertIs<AntdGrpcClient>(grpc)
        grpc.close()
    }

    @Test
    fun `factory rejects unknown transport`() {
        try {
            AntdClient.create("websocket")
            throw AssertionError("Should have thrown")
        } catch (e: IllegalArgumentException) {
            assert(e.message!!.contains("Unknown transport"))
        }
    }

    @Test
    fun `models have correct structure`() {
        val health = HealthStatus(true, "local")
        assertEquals(true, health.ok)
        assertEquals("local", health.network)

        val put = PutResult("100", "abc123")
        assertEquals("100", put.cost)
        assertEquals("abc123", put.address)

        val archiveEntry = ArchiveEntry("/file.txt", "addr", 1000UL, 2000UL, 512UL)
        val archive = Archive(listOf(archiveEntry))
        assertEquals(1, archive.entries.size)
    }

    @Test
    fun `exception hierarchy is correct`() {
        assertIs<AntdException>(NotFoundException("not found"))
        assertIs<AntdException>(AlreadyExistsException("exists"))
        assertIs<AntdException>(ForkException("fork"))
        assertIs<AntdException>(BadRequestException("bad"))
        assertIs<AntdException>(PaymentException("pay"))
        assertIs<AntdException>(NetworkException("net"))
        assertIs<AntdException>(TooLargeException("big"))
        assertIs<AntdException>(InternalException("err"))

        assertEquals(404, NotFoundException("x").statusCode)
        assertEquals(409, AlreadyExistsException("x").statusCode)
        assertEquals(400, BadRequestException("x").statusCode)
        assertEquals(402, PaymentException("x").statusCode)
        assertEquals(502, NetworkException("x").statusCode)
        assertEquals(413, TooLargeException("x").statusCode)
        assertEquals(500, InternalException("x").statusCode)
    }

    @Test
    fun `exception mapping from HTTP status codes`() {
        assertIs<BadRequestException>(ExceptionMapping.fromHttpStatus(400, "bad"))
        assertIs<PaymentException>(ExceptionMapping.fromHttpStatus(402, "pay"))
        assertIs<NotFoundException>(ExceptionMapping.fromHttpStatus(404, "nf"))
        assertIs<AlreadyExistsException>(ExceptionMapping.fromHttpStatus(409, "exists"))
        assertIs<TooLargeException>(ExceptionMapping.fromHttpStatus(413, "big"))
        assertIs<InternalException>(ExceptionMapping.fromHttpStatus(500, "err"))
        assertIs<NetworkException>(ExceptionMapping.fromHttpStatus(502, "net"))
        assertIs<AntdException>(ExceptionMapping.fromHttpStatus(418, "teapot"))
    }
}
