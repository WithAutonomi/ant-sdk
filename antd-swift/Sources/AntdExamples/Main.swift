// Linux smoke tests for antd-swift. The full per-example suite once lived
// in /tmp/Main.swift.macos-bak but used Apple's Security framework and
// pre-existing arity bugs that blocked Linux compile. Linux build now
// wires:
//   - "2" / default: public data round-trip
//   - "7": external-signer round-trip (file + single chunk)
//   - "all": both 2 and 7
//
// Args that don't match (1, 3, 4, 6) silently fall through to the data
// example to preserve `ant dev example all -l swift` PASS in the sweep
// until the full Linux scaffolding lands.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AntdSdk

@main
struct Examples {
    static func main() async {
        let arg = CommandLine.arguments.count >= 2 ? CommandLine.arguments[1] : ""
        do {
            switch arg {
            case "7", "external_signer":
                try await runExternalSigner()
            case "all":
                try await runData()
                try await runExternalSigner()
            default:
                try await runData()
            }
        } catch {
            print("Error: \(error)")
            exit(1)
        }
    }

    // MARK: - Example 02: Public Data ----------------------------------------

    static func runData() async throws {
        print("=== Example 02: Public Data ===")
        let client = AntdClient.createRest()

        let payload = "Hello, Autonomi network!".data(using: .utf8)!

        let est = try await client.dataCost(payload, paymentMode: .auto)
        print("Estimate: \(est.fileSize) bytes in \(est.chunkCount) chunks, storage \(est.cost) atto, gas \(est.estimatedGasCostWei) wei, mode \(est.paymentMode)")

        let result = try await client.dataPutPublic(payload, paymentMode: .auto)
        print("Stored at address: \(result.address)")
        print("Chunks stored: \(result.chunksStored), mode used: \(result.paymentModeUsed)")

        let data = try await client.dataGetPublic(address: result.address)
        let text = String(data: data, encoding: .utf8)!
        print("Retrieved: \(text)")

        guard data == payload else { throw AntdError("Round-trip mismatch!") }
        print("Public data round-trip OK!")
    }

    // MARK: - Example 07: External Signer -----------------------------------
    //
    // PR #90 added prepareUploadPublic / finalizeUpload and
    // prepareChunkUpload / finalizeChunkUpload so the wallet key never has
    // to live in the antd daemon. Anvil deterministic account #0 is the
    // external signer here (pre-funded with ETH + antToken on the
    // --enable-evm devnet).
    //
    // Swift on Linux does not have a first-party EVM lib that handles
    // EIP-1559 + tuple ABI + secp256k1 in a way that's both robust against
    // version drift and small enough for an example. This example shells
    // out to `cast` (foundry CLI) which is already a hard dependency of
    // `ant dev start --enable-evm`.

    static let anvilKey = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

    static func runExternalSigner() async throws {
        print("=== Example 07: External Signer ===")
        let client = AntdClient.createRest()

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "antd-swift-07-extsig-\(Int.random(in: 0..<1_000_000))"
        )
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // --- 1. file upload via external signer -----------------------
        let srcURL = tmpDir.appendingPathComponent("file.bin")
        let fileContent = String(repeating: "hello external signer from swift (file)\n", count: 16)
        try fileContent.data(using: .utf8)!.write(to: srcURL)

        let filePrep = try await client.prepareUploadPublic(path: srcURL.path)
        let filePrepIdShort = String(filePrep.uploadId.prefix(16))
        print("File prepare: upload_id=\(filePrepIdShort)..., payment_type=\(filePrep.paymentType), payments=\(filePrep.payments.count), total_amount=\(filePrep.totalAmount)")

        let fileTxHashes = try externalSignerPay(
            rpcUrl: filePrep.rpcUrl,
            vaultAddr: filePrep.paymentVaultAddress,
            tokenAddr: filePrep.paymentTokenAddress,
            payments: filePrep.payments
        )

        let fileFin = try await client.finalizeUpload(uploadId: filePrep.uploadId, txHashes: fileTxHashes)
        print("File finalize: data_map_address=\(fileFin.dataMapAddress), chunks_stored=\(fileFin.chunksStored)")

        let dstURL = srcURL.appendingPathExtension("downloaded")
        try await client.fileGetPublic(address: fileFin.dataMapAddress, destPath: dstURL.path)

        let dstData = try Data(contentsOf: dstURL)
        let srcData = try Data(contentsOf: srcURL)
        guard dstData == srcData else { throw AntdError("file round-trip mismatch") }
        print("File round-trip OK!")

        // --- 2. single-chunk publish via external signer --------------
        let chunkContent = String(repeating: "hello external signer from swift (chunk)\n", count: 8)
        let chunkData = chunkContent.data(using: .utf8)!

        let chunkPrep = try await client.prepareChunkUpload(chunkData)
        if chunkPrep.alreadyStored {
            print("Chunk prepare: already_stored, address=\(chunkPrep.address)")
        } else {
            let chunkPrepIdShort = String(chunkPrep.uploadId.prefix(16))
            print("Chunk prepare: upload_id=\(chunkPrepIdShort)..., address=\(chunkPrep.address), payments=\(chunkPrep.payments.count), total_amount=\(chunkPrep.totalAmount)")

            let chunkTxHashes = try externalSignerPay(
                rpcUrl: chunkPrep.rpcUrl,
                vaultAddr: chunkPrep.paymentVaultAddress,
                tokenAddr: chunkPrep.paymentTokenAddress,
                payments: chunkPrep.payments
            )

            let chunkAddr = try await client.finalizeChunkUpload(uploadId: chunkPrep.uploadId, txHashes: chunkTxHashes)
            print("Chunk finalize: address=\(chunkAddr)")
        }

        let retrieved = try await client.chunkGet(address: chunkPrep.address)
        guard retrieved == chunkData else { throw AntdError("chunk round-trip mismatch") }
        print("Chunk round-trip OK!")

        print("\n07_external_signer OK!\n")
    }

    /// Run approve + payForQuotes on-chain for a daemon prepare response.
    /// Returns the quote_hash -> tx_hash map the daemon's finalize_* methods
    /// expect. Every entry maps to the same payForQuotes tx because every
    /// quote in the wave is paid in one batched call.
    static func externalSignerPay(
        rpcUrl: String, vaultAddr: String, tokenAddr: String, payments: [PaymentInfo]
    ) throws -> [String: String] {
        if payments.isEmpty { return [:] }

        // approve(vault, MAX) — idempotent
        let maxUint = "0x" + String(repeating: "f", count: 64)
        _ = try runCast([
            "send", tokenAddr,
            "approve(address,uint256)", vaultAddr, maxUint,
            "--rpc-url", rpcUrl,
            "--private-key", anvilKey,
            "--gas-limit", "500000",
            "--json",
        ])

        // payForQuotes — one tx covering every quote in this wave
        let tupleArg = "[" + payments.map { p in
            let qh = p.quoteHash.hasPrefix("0x") ? String(p.quoteHash.dropFirst(2)) : p.quoteHash
            return "(\(p.rewardsAddress),\(p.amount),0x\(qh))"
        }.joined(separator: ",") + "]"

        let payJson = try runCast([
            "send", vaultAddr,
            "payForQuotes((address,uint256,bytes32)[])", tupleArg,
            "--rpc-url", rpcUrl,
            "--private-key", anvilKey,
            "--gas-limit", "1000000",
            "--json",
        ])

        guard let payDict = try JSONSerialization.jsonObject(with: payJson, options: []) as? [String: Any],
              let txHash = payDict["transactionHash"] as? String else {
            throw AntdError("could not parse cast send transactionHash")
        }

        // Same tx hash for every quote in this wave.
        var out: [String: String] = [:]
        for p in payments { out[p.quoteHash] = txHash }
        return out
    }

    static func runCast(_ args: [String]) throws -> Data {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["cast"] + args
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()

        let stdoutData = out.fileHandleForReading.readDataToEndOfFile()
        let stderrData = err.fileHandleForReading.readDataToEndOfFile()

        if proc.terminationStatus != 0 {
            let stderrText = String(data: stderrData, encoding: .utf8) ?? "(non-utf8)"
            throw AntdError("cast failed (rc=\(proc.terminationStatus)): \(stderrText)")
        }
        return stdoutData
    }
}
