package com.autonomi.sdk

import antd.v1.Wallet.GetWalletAddressRequest
import antd.v1.Wallet.GetWalletAddressResponse
import antd.v1.Wallet.GetWalletBalanceRequest
import antd.v1.Wallet.GetWalletBalanceResponse
import antd.v1.Wallet.WalletApproveRequest
import antd.v1.Wallet.WalletApproveResponse
import antd.v1.WalletServiceGrpcKt
import io.grpc.ManagedChannel
import io.grpc.Server
import io.grpc.Status
import io.grpc.inprocess.InProcessChannelBuilder
import io.grpc.inprocess.InProcessServerBuilder
import kotlinx.coroutines.runBlocking
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.assertFailsWith

/**
 * V2-286 wallet wire-mapping tests for AntdGrpcClient. Spins up an in-process
 * grpc-kotlin server with a mock WalletService, then dials with a real
 * AntdGrpcClient. Mirrors the antd-rust / antd-go / antd-py / antd-java
 * suites.
 */
class GrpcWalletTest {

    private lateinit var server: Server
    private lateinit var channel: ManagedChannel
    private lateinit var client: AntdGrpcClient

    private class MockWallet : WalletServiceGrpcKt.WalletServiceCoroutineImplBase() {
        override suspend fun getAddress(request: GetWalletAddressRequest): GetWalletAddressResponse =
            GetWalletAddressResponse.newBuilder()
                .setAddress("0xabc1234567890abcdef1234567890abcdef123456")
                .build()

        override suspend fun getBalance(request: GetWalletBalanceRequest): GetWalletBalanceResponse =
            GetWalletBalanceResponse.newBuilder()
                .setBalance("1000000000000000000")
                .setGasBalance("500000000000000000")
                .build()

        override suspend fun approve(request: WalletApproveRequest): WalletApproveResponse =
            WalletApproveResponse.newBuilder()
                .setApproved(true)
                .build()
    }

    private fun startServer(service: WalletServiceGrpcKt.WalletServiceCoroutineImplBase) {
        val serverName = InProcessServerBuilder.generateName()
        server = InProcessServerBuilder.forName(serverName)
            .directExecutor()
            .addService(service)
            .build()
            .start()
        channel = InProcessChannelBuilder.forName(serverName).directExecutor().build()
        client = AntdGrpcClient(channel)
    }

    @BeforeTest
    fun setUp() {
        startServer(MockWallet())
    }

    @AfterTest
    fun tearDown() {
        client.close()
        channel.shutdownNow()
        server.shutdownNow()
    }

    @Test
    fun `walletAddress returns address`() = runBlocking {
        val r = client.walletAddress()
        assertEquals("0xabc1234567890abcdef1234567890abcdef123456", r.address)
    }

    @Test
    fun `walletBalance returns balances`() = runBlocking {
        val r = client.walletBalance()
        assertEquals("1000000000000000000", r.balance)
        assertEquals("500000000000000000", r.gasBalance)
    }

    @Test
    fun `walletApprove returns true`() = runBlocking {
        assertTrue(client.walletApprove())
    }

    /**
     * Daemon emits gRPC FailedPrecondition for "wallet not configured"; the
     * established mapping (ExceptionMapping.fromGrpcStatus / wrap()) surfaces
     * this as PaymentException. (Semantic a bit off vs REST's 503 but matches
     * every SDK.)
     */
    @Test
    fun `walletAddress unconfigured raises PaymentException`() = runBlocking {
        // Tear down the happy-path server and replace with an "unconfigured" one.
        client.close()
        channel.shutdownNow()
        server.shutdownNow()
        startServer(object : WalletServiceGrpcKt.WalletServiceCoroutineImplBase() {
            override suspend fun getAddress(request: GetWalletAddressRequest): GetWalletAddressResponse =
                throw Status.FAILED_PRECONDITION
                    .withDescription("wallet not configured — set AUTONOMI_WALLET_KEY")
                    .asRuntimeException()
        })
        val ex = assertFailsWith<PaymentException> { client.walletAddress() }
        assertTrue(ex.message!!.contains("wallet not configured"))
    }
}
