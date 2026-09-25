package com.autonomi.examples;

import com.autonomi.antd.AntdClient;
import com.autonomi.antd.errors.PartialUploadException;
import com.autonomi.antd.models.FinalizeUploadResult;
import com.autonomi.antd.models.PaymentInfo;
import com.autonomi.antd.models.PrepareChunkResult;
import com.autonomi.antd.models.PrepareUploadResult;

import org.web3j.abi.FunctionEncoder;
import org.web3j.abi.TypeReference;
import org.web3j.abi.datatypes.Address;
import org.web3j.abi.datatypes.DynamicArray;
import org.web3j.abi.datatypes.Function;
import org.web3j.abi.datatypes.StaticStruct;
import org.web3j.abi.datatypes.generated.Bytes32;
import org.web3j.abi.datatypes.generated.Uint256;
import org.web3j.crypto.Credentials;
import org.web3j.protocol.Web3j;
import org.web3j.protocol.core.DefaultBlockParameterName;
import org.web3j.protocol.core.methods.response.EthGetTransactionCount;
import org.web3j.protocol.core.methods.response.EthSendTransaction;
import org.web3j.protocol.core.methods.response.TransactionReceipt;
import org.web3j.protocol.http.HttpService;
import org.web3j.tx.RawTransactionManager;
import org.web3j.tx.response.PollingTransactionReceiptProcessor;

import java.math.BigInteger;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * Example 07 — External-signer flow: public file + single-chunk publish.
 *
 * <p>PR #90 added prepareUploadPublic / finalizeUpload and prepareChunkUpload /
 * finalizeChunkUpload so the wallet key never has to live in the antd daemon.
 * This example uses anvil deterministic account #0 as the external signer
 * and exercises both round-trips end-to-end.
 *
 * <p>See docs/external-signer-flow.md for the full reference; the IPaymentVault
 * function selector and ABI layout are baked into the {@link DataPayment}
 * struct and the {@code payForQuotes} {@link Function} declaration. The file
 * finalize goes through {@link #finalizeWithRetry}, which shows how to resume
 * a partial store against the same payment (docs/external-signer-flow.md §6).
 */
public class Example07ExternalSigner {

    /** Attempts {@link #finalizeWithRetry} makes before declaring the upload stuck. */
    private static final int FINALIZE_MAX_ATTEMPTS = 5;

    // Anvil deterministic account #0. Pre-funded with ETH (gas) and antToken
    // (storage payment) by `ant dev start --enable-evm` devnet genesis. Never
    // use this key anywhere except a throw-away local devnet.
    // Web3j's Credentials.create takes an unprefixed hex string.
    private static final String ANVIL_KEY =
            "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
    private static final BigInteger MAX_UINT256 =
            BigInteger.ONE.shiftLeft(256).subtract(BigInteger.ONE);

    /**
     * payForQuotes' tuple struct: (address, uint256, bytes32). All fields are
     * static-size, so this extends StaticStruct — web3j otherwise inserts a
     * per-struct offset+length prefix in the encoded calldata and the tx
     * reverts with a malformed-args mismatch.
     */
    public static class DataPayment extends StaticStruct {
        public DataPayment(Address rewardsAddress, Uint256 amount, Bytes32 quoteHash) {
            super(rewardsAddress, amount, quoteHash);
        }
    }

    public static void main(String[] args) throws Exception {
        Path tmp = Files.createTempDirectory("antd-java-07-extsig-");
        try (AntdClient client = new AntdClient()) {
            Credentials credentials = Credentials.create(ANVIL_KEY);

            // --- 1. file upload via external signer ---------------------
            byte[] fileContent = "hello external signer from java (file)\n".repeat(16)
                    .getBytes(java.nio.charset.StandardCharsets.UTF_8);
            Path src = tmp.resolve("file.bin");
            Files.write(src, fileContent);

            PrepareUploadResult filePrep = client.prepareUploadPublic(src.toString());
            System.out.printf(
                    "File prepare: upload_id=%s..., payment_type=%s, payments=%d, total_amount=%s%n",
                    filePrep.uploadId().substring(0, 16),
                    filePrep.paymentType(),
                    filePrep.payments().size(),
                    filePrep.totalAmount());

            Map<String, String> fileTxHashes = externalSignerPay(
                    filePrep.rpcUrl(), filePrep.paymentVaultAddress(),
                    filePrep.paymentTokenAddress(), filePrep.payments(), credentials);
            FinalizeUploadResult fileFin = finalizeWithRetry(client, filePrep.uploadId(), fileTxHashes);
            System.out.printf("File finalize: data_map_address=%s, chunks_stored=%d%n",
                    fileFin.dataMapAddress(), fileFin.chunksStored());

            Path dst = src.resolveSibling("file.bin.downloaded");
            client.fileGetPublic(fileFin.dataMapAddress(), dst.toString());
            byte[] downloaded = Files.readAllBytes(dst);
            if (!Arrays.equals(downloaded, fileContent)) {
                throw new RuntimeException("file round-trip mismatch");
            }
            System.out.println("File round-trip OK!");

            // --- 2. single-chunk publish via external signer ------------
            byte[] chunkData = "hello external signer from java (chunk)\n".repeat(8)
                    .getBytes(java.nio.charset.StandardCharsets.UTF_8);
            PrepareChunkResult chunkPrep = client.prepareChunkUpload(chunkData);
            if (chunkPrep.alreadyStored()) {
                System.out.printf("Chunk prepare: already_stored, address=%s%n", chunkPrep.address());
            } else {
                System.out.printf(
                        "Chunk prepare: upload_id=%s..., address=%s, payments=%d, total_amount=%s%n",
                        chunkPrep.uploadId().substring(0, 16),
                        chunkPrep.address(),
                        chunkPrep.payments().size(),
                        chunkPrep.totalAmount());
                Map<String, String> chunkTxHashes = externalSignerPay(
                        chunkPrep.rpcUrl(), chunkPrep.paymentVaultAddress(),
                        chunkPrep.paymentTokenAddress(), chunkPrep.payments(), credentials);
                String addr = client.finalizeChunkUpload(chunkPrep.uploadId(), chunkTxHashes);
                if (!addr.equals(chunkPrep.address())) {
                    throw new RuntimeException(
                            "chunk address mismatch: " + addr + " != " + chunkPrep.address());
                }
                System.out.printf("Chunk finalize: address=%s%n", addr);
            }

            byte[] chunkGot = client.chunkGet(chunkPrep.address());
            if (!Arrays.equals(chunkGot, chunkData)) {
                throw new RuntimeException("chunk round-trip mismatch");
            }
            System.out.println("Chunk round-trip OK!");

            System.out.println("\n07_external_signer OK!");
        } finally {
            try (Stream<Path> walk = Files.walk(tmp)) {
                walk.sorted(Comparator.reverseOrder()).forEach(p -> {
                    try { Files.deleteIfExists(p); } catch (Exception ignored) {}
                });
            }
        }
    }

    /**
     * Finalize, resuming a partial store against the same payment.
     *
     * <p>When some chunks stay unstored after the daemon's own retries,
     * {@code finalizeUpload} throws {@link PartialUploadException}. The helper
     * retries only when {@code isRetryable()}: the daemon (antd &gt;= 0.14.0)
     * kept the paid attempt under the same upload_id, so calling finalize
     * again with the <b>same</b> upload_id and tx hashes stores the remainder
     * against the same payment — no re-prepare, no second signature, no double
     * payment. It never prepares or pays itself.
     *
     * <p>Whenever it stops on a partial store it rethrows the last
     * {@code PartialUploadException} unchanged, so the caller keeps the typed
     * error with its counts and both flags:
     * <ul>
     *   <li>attempts exhausted, or {@code chunksFailed} stopped shrinking (a
     *       persistent failure throws on every call): the paid attempt is still
     *       retained under the upload_id;</li>
     *   <li>{@code isRetentionKnown() && !isRetryable()}: the daemon confirmed
     *       nothing was retained, so the caller may re-prepare the same content
     *       (already-stored chunks are skipped);</li>
     *   <li>{@code !isRetentionKnown()}: retention is unknown and the daemon
     *       may still hold the paid attempt, so the caller must not re-prepare
     *       or pay again on this alone — keep the upload_id and tx hashes and
     *       reconcile first;</li>
     *   <li>the thread was interrupted during the backoff: the interrupt
     *       status is restored and the {@code InterruptedException} is attached
     *       as suppressed.</li>
     * </ul>
     * Any other exception from finalize propagates untouched, without a retry.
     */
    static FinalizeUploadResult finalizeWithRetry(
            AntdClient client, String uploadId, Map<String, String> txHashes) {
        return finalizeWithRetry(client::finalizeUpload, uploadId, txHashes,
                FINALIZE_MAX_ATTEMPTS, Thread::sleep);
    }

    /** One finalize call: {@link AntdClient#finalizeUpload} here, a stub in tests. */
    @FunctionalInterface
    interface FinalizeCall {
        FinalizeUploadResult call(String uploadId, Map<String, String> txHashes);
    }

    /** Pause between attempts: {@link Thread#sleep(long)} here, a recorder in tests. */
    @FunctionalInterface
    interface Backoff {
        void pause(long millis) throws InterruptedException;
    }

    /**
     * {@link #finalizeWithRetry(AntdClient, String, Map)} with the finalize
     * call, attempt cap and backoff injected so the loop can be tested
     * directly.
     */
    static FinalizeUploadResult finalizeWithRetry(
            FinalizeCall finalizeCall, String uploadId, Map<String, String> txHashes,
            int maxAttempts, Backoff backoff) {
        long lastFailed = 0;
        for (int attempt = 1; ; attempt++) {
            PartialUploadException partial;
            try {
                return finalizeCall.call(uploadId, txHashes); // every chunk stored
            } catch (PartialUploadException e) {
                partial = e;
            }
            if (!partial.isRetryable()) {
                if (!partial.isRetentionKnown()) {
                    System.err.printf(
                            "finalize: partial store with unknown retention; keep upload_id %s and its "
                                    + "tx hashes and reconcile before re-preparing or paying again%n",
                            uploadId);
                }
                throw partial;
            }
            boolean stalled = attempt > 1 && partial.getChunksFailed() >= lastFailed;
            if (attempt >= maxAttempts || stalled) {
                System.err.printf(
                        "finalize %s after %d attempt(s): %d/%d chunks stored, %d still unstored "
                                + "(paid attempt retained under upload_id %s)%n",
                        stalled ? "stalled" : "gave up", attempt, partial.getChunksStored(),
                        partial.getTotalChunks(), partial.getChunksFailed(), uploadId);
                throw partial;
            }
            lastFailed = partial.getChunksFailed();
            System.out.printf(
                    "finalize stored %d/%d chunks, %d still unstored — retrying against the same payment "
                            + "(attempt %d/%d)%n",
                    partial.getChunksStored(), partial.getTotalChunks(), partial.getChunksFailed(),
                    attempt + 1, maxAttempts);
            try {
                backoff.pause(attempt * 2_000L);
            } catch (InterruptedException interrupted) {
                Thread.currentThread().interrupt();
                partial.addSuppressed(interrupted);
                throw partial;
            }
        }
    }

    /**
     * Run approve + payForQuotes on-chain for a daemon prepare response.
     * Returns the quote_hash -> tx_hash map the daemon's finalize_* methods
     * expect. Every entry maps to the same payForQuotes tx because every
     * quote in the wave is paid in one batched call.
     */
    private static Map<String, String> externalSignerPay(
            String rpcUrl,
            String vaultAddress,
            String tokenAddress,
            List<PaymentInfo> payments,
            Credentials credentials) throws Exception {

        // No on-chain work when every quoted chunk is already on-network.
        if (payments.isEmpty()) return Map.of();

        Web3j web3 = Web3j.build(new HttpService(rpcUrl));
        try {
            BigInteger chainId = web3.ethChainId().send().getChainId();
            RawTransactionManager txManager = new RawTransactionManager(
                    web3, credentials, chainId.longValueExact(),
                    new PollingTransactionReceiptProcessor(web3, 100, 60));

            BigInteger gasPrice = web3.ethGasPrice().send().getGasPrice();

            // approve(vault, MAX) — idempotent; using MAX so subsequent flows
            // in this run skip a fresh approval.
            Function approveFn = new Function(
                    "approve",
                    Arrays.asList(new Address(vaultAddress), new Uint256(MAX_UINT256)),
                    Collections.emptyList());
            String approveData = FunctionEncoder.encode(approveFn);
            EthSendTransaction approveResp = txManager.sendTransaction(
                    gasPrice, BigInteger.valueOf(500_000), tokenAddress, approveData, BigInteger.ZERO);
            if (approveResp.hasError()) {
                throw new RuntimeException("approve send error: " + approveResp.getError().getMessage());
            }
            TransactionReceipt approveRcpt = waitMined(web3, approveResp.getTransactionHash());
            if (!approveRcpt.isStatusOK()) {
                throw new RuntimeException("approve reverted: " + approveRcpt.getTransactionHash());
            }

            // payForQuotes — one tx covering every quote in this wave.
            List<DataPayment> structs = payments.stream().map(p -> {
                String qhHex = p.quoteHash().startsWith("0x") ? p.quoteHash().substring(2) : p.quoteHash();
                byte[] qhBytes = hexToBytes(qhHex);
                return new DataPayment(
                        new Address(p.rewardsAddress()),
                        new Uint256(new BigInteger(p.amount())),
                        new Bytes32(qhBytes));
            }).collect(Collectors.toList());

            @SuppressWarnings({"unchecked", "rawtypes"})
            Function payFn = new Function(
                    "payForQuotes",
                    Collections.singletonList(new DynamicArray(DataPayment.class, structs)),
                    Collections.emptyList());
            String payData = FunctionEncoder.encode(payFn);
            EthSendTransaction payResp = txManager.sendTransaction(
                    gasPrice, BigInteger.valueOf(1_000_000), vaultAddress, payData, BigInteger.ZERO);
            if (payResp.hasError()) {
                throw new RuntimeException("payForQuotes send error: " + payResp.getError().getMessage());
            }
            TransactionReceipt payRcpt = waitMined(web3, payResp.getTransactionHash());
            if (!payRcpt.isStatusOK()) {
                throw new RuntimeException("payForQuotes reverted: " + payRcpt.getTransactionHash());
            }

            // Every quote in this wave was paid in the same call.
            Map<String, String> out = new HashMap<>(payments.size());
            String txHash = payRcpt.getTransactionHash();
            for (PaymentInfo p : payments) out.put(p.quoteHash(), txHash);
            return out;
        } finally {
            web3.shutdown();
        }
    }

    private static TransactionReceipt waitMined(Web3j web3, String txHash) throws Exception {
        // Anvil instant-mines, so polling resolves within ~100 ms.
        for (int i = 0; i < 600; i++) {
            var rcpt = web3.ethGetTransactionReceipt(txHash).send().getTransactionReceipt();
            if (rcpt.isPresent()) return rcpt.get();
            Thread.sleep(100);
        }
        throw new RuntimeException("tx receipt timeout: " + txHash);
    }

    private static byte[] hexToBytes(String hex) {
        int len = hex.length();
        byte[] out = new byte[len / 2];
        for (int i = 0; i < len; i += 2) {
            out[i / 2] = (byte) ((Character.digit(hex.charAt(i), 16) << 4)
                    + Character.digit(hex.charAt(i + 1), 16));
        }
        return out;
    }
}
