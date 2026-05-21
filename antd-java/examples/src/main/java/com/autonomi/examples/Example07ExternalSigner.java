package com.autonomi.examples;

import com.autonomi.antd.AntdClient;
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
 * struct and the {@code payForQuotes} {@link Function} declaration.
 */
public class Example07ExternalSigner {

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
            FinalizeUploadResult fileFin = client.finalizeUpload(filePrep.uploadId(), fileTxHashes);
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
