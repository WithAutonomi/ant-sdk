package com.autonomi.examples

import com.autonomi.sdk.AntdClient
import com.autonomi.sdk.PaymentInfo

import org.web3j.abi.FunctionEncoder
import org.web3j.abi.datatypes.Address
import org.web3j.abi.datatypes.DynamicArray
import org.web3j.abi.datatypes.Function
import org.web3j.abi.datatypes.StaticStruct
import org.web3j.abi.datatypes.generated.Bytes32
import org.web3j.abi.datatypes.generated.Uint256
import org.web3j.crypto.Credentials
import org.web3j.protocol.Web3j
import org.web3j.protocol.core.methods.response.TransactionReceipt
import org.web3j.protocol.http.HttpService
import org.web3j.tx.RawTransactionManager
import org.web3j.tx.response.PollingTransactionReceiptProcessor

import java.io.File
import java.math.BigInteger
import java.nio.file.Files

// Anvil deterministic account #0. Pre-funded with ETH (gas) and antToken
// (storage payment) by `ant dev start --enable-evm` devnet genesis. Never
// use this key anywhere except a throw-away local devnet.
//
// Web3j's Credentials.create takes the unprefixed hex string.
private const val ANVIL_KEY =
    "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

private val MAX_UINT256: BigInteger = BigInteger.ONE.shiftLeft(256).subtract(BigInteger.ONE)

/**
 * payForQuotes' tuple struct: (address, uint256, bytes32). All fields are
 * static-size so this MUST extend StaticStruct; inheriting DynamicStruct
 * makes web3j insert per-struct offset prefixes which the contract rejects.
 */
class DataPayment(rewardsAddress: Address, amount: Uint256, quoteHash: Bytes32) :
    StaticStruct(rewardsAddress, amount, quoteHash)

/**
 * Example 07 — External-signer flow: public file + single-chunk publish.
 *
 * Uses anvil deterministic account #0 as the external signer and exercises
 * both round-trips end-to-end against `ant dev start --enable-evm`.
 *
 * See docs/external-signer-flow.md for the full reference; the IPaymentVault
 * function selector and ABI layout are baked into [DataPayment] above and
 * the `payForQuotes` [Function] declaration below.
 */
suspend fun example07ExternalSigner() {
    println("=== Example 07: External Signer ===")
    val client = AntdClient.createRest()
    val credentials = Credentials.create(ANVIL_KEY)

    val tmpDir = Files.createTempDirectory("antd-kotlin-07-extsig-").toFile()
    try {
        // --- 1. file upload via external signer ---------------------
        val fileBytes = "hello external signer from kotlin (file)\n".repeat(16).toByteArray()
        val src = File(tmpDir, "file.bin").also { it.writeBytes(fileBytes) }

        val filePrep = client.prepareUploadPublic(src.absolutePath)
        println(
            "File prepare: upload_id=${filePrep.uploadId.take(16)}..., " +
                "payment_type=${filePrep.paymentType}, " +
                "payments=${filePrep.payments.size}, total_amount=${filePrep.totalAmount}"
        )

        val fileTxHashes = externalSignerPay(
            filePrep.rpcUrl, filePrep.paymentVaultAddress, filePrep.paymentTokenAddress,
            filePrep.payments, credentials
        )
        val fileFin = client.finalizeUpload(filePrep.uploadId, fileTxHashes)
        println(
            "File finalize: data_map_address=${fileFin.dataMapAddress}, " +
                "chunks_stored=${fileFin.chunksStored}"
        )

        val dst = File(tmpDir, "file.bin.downloaded")
        client.fileGetPublic(fileFin.dataMapAddress, dst.absolutePath)
        if (!dst.readBytes().contentEquals(fileBytes)) {
            throw RuntimeException("file round-trip mismatch")
        }
        println("File round-trip OK!")

        // --- 2. single-chunk publish via external signer ------------
        val chunkData = "hello external signer from kotlin (chunk)\n".repeat(8).toByteArray()
        val chunkPrep = client.prepareChunkUpload(chunkData)
        if (chunkPrep.alreadyStored) {
            println("Chunk prepare: already_stored, address=${chunkPrep.address}")
        } else {
            println(
                "Chunk prepare: upload_id=${chunkPrep.uploadId.take(16)}..., " +
                    "address=${chunkPrep.address}, payments=${chunkPrep.payments.size}, " +
                    "total_amount=${chunkPrep.totalAmount}"
            )
            val chunkTxHashes = externalSignerPay(
                chunkPrep.rpcUrl, chunkPrep.paymentVaultAddress, chunkPrep.paymentTokenAddress,
                chunkPrep.payments, credentials
            )
            val addr = client.finalizeChunkUpload(chunkPrep.uploadId, chunkTxHashes)
            if (addr != chunkPrep.address) {
                throw RuntimeException("chunk address mismatch: $addr != ${chunkPrep.address}")
            }
            println("Chunk finalize: address=$addr")
        }

        val chunkGot = client.chunkGet(chunkPrep.address)
        if (!chunkGot.contentEquals(chunkData)) {
            throw RuntimeException("chunk round-trip mismatch")
        }
        println("Chunk round-trip OK!")

        println("\n07_external_signer OK!\n")
    } finally {
        client.close()
        tmpDir.deleteRecursively()
    }
}

/**
 * Run approve + payForQuotes on-chain for a daemon prepare response.
 * Returns the quote_hash -> tx_hash map the daemon's finalize_* methods
 * expect. Every entry maps to the same payForQuotes tx because every
 * quote in the wave is paid in one batched call.
 */
private fun externalSignerPay(
    rpcUrl: String,
    vaultAddress: String,
    tokenAddress: String,
    payments: List<PaymentInfo>,
    credentials: Credentials,
): Map<String, String> {
    // No on-chain work when every quoted chunk is already on-network.
    if (payments.isEmpty()) return emptyMap()

    val web3 = Web3j.build(HttpService(rpcUrl))
    try {
        val chainId = web3.ethChainId().send().chainId.toLong()
        val txManager = RawTransactionManager(
            web3, credentials, chainId,
            PollingTransactionReceiptProcessor(web3, 100, 60),
        )
        val gasPrice: BigInteger = web3.ethGasPrice().send().gasPrice

        // approve(vault, MAX) — idempotent and cheap; example uses MAX so
        // subsequent flows in this run skip a fresh approval.
        val approveFn = Function(
            "approve",
            listOf(Address(vaultAddress), Uint256(MAX_UINT256)),
            emptyList(),
        )
        val approveData = FunctionEncoder.encode(approveFn)
        val approveResp = txManager.sendTransaction(
            gasPrice, BigInteger.valueOf(500_000L), tokenAddress, approveData, BigInteger.ZERO,
        )
        if (approveResp.hasError()) {
            throw RuntimeException("approve send error: ${approveResp.error.message}")
        }
        val approveRcpt = waitMined(web3, approveResp.transactionHash)
        if (!approveRcpt.isStatusOK) {
            throw RuntimeException("approve reverted: ${approveRcpt.transactionHash}")
        }

        // payForQuotes — one tx covering every quote in this wave.
        val structs: List<DataPayment> = payments.map { p ->
            val qhHex = p.quoteHash.removePrefix("0x")
            DataPayment(
                Address(p.rewardsAddress),
                Uint256(BigInteger(p.amount)),
                Bytes32(hexToBytes(qhHex)),
            )
        }
        @Suppress("UNCHECKED_CAST")
        val payFn = Function(
            "payForQuotes",
            listOf(DynamicArray(DataPayment::class.java, structs)),
            emptyList(),
        )
        val payData = FunctionEncoder.encode(payFn)
        val payResp = txManager.sendTransaction(
            gasPrice, BigInteger.valueOf(1_000_000L), vaultAddress, payData, BigInteger.ZERO,
        )
        if (payResp.hasError()) {
            throw RuntimeException("payForQuotes send error: ${payResp.error.message}")
        }
        val payRcpt = waitMined(web3, payResp.transactionHash)
        if (!payRcpt.isStatusOK) {
            throw RuntimeException("payForQuotes reverted: ${payRcpt.transactionHash}")
        }

        // Every quote in this wave was paid in the same call.
        val txHash = payRcpt.transactionHash
        return payments.associate { it.quoteHash to txHash }
    } finally {
        web3.shutdown()
    }
}

private fun waitMined(web3: Web3j, txHash: String): TransactionReceipt {
    // Anvil instant-mines, so polling resolves within ~100 ms.
    repeat(600) {
        val rcpt = web3.ethGetTransactionReceipt(txHash).send().transactionReceipt
        if (rcpt.isPresent) return rcpt.get()
        Thread.sleep(100)
    }
    throw RuntimeException("tx receipt timeout: $txHash")
}

private fun hexToBytes(hex: String): ByteArray {
    val out = ByteArray(hex.length / 2)
    for (i in out.indices) {
        out[i] = ((Character.digit(hex[i * 2], 16) shl 4) +
            Character.digit(hex[i * 2 + 1], 16)).toByte()
    }
    return out
}
