// Linux smoke tests for antd-swift. The full per-example suite once lived
// in /tmp/Main.swift.macos-bak but used Apple's Security framework and
// pre-existing arity bugs that blocked Linux compile. Linux build now
// wires:
//   - "2" / default: public data round-trip
//   - "7": external-signer round-trip (file + single chunk)
//   - "9" / "pointers": pointer create → update → resolve → finality.
//     Pays for every write and needs a never-written owner in
//     ANTD_POINTER_OWNER, so it runs only when named, never under "all".
//   - "all": 2 and 7
//
// Args that don't match (1, 3, 4, 6) silently fall through to the data
// example to preserve `ant dev example all -l swift` PASS in the sweep
// until the full Linux scaffolding lands.
//
// "10" / "manifests" builds a manifest of two public uploads and decodes its
// link. It needs the antd release after 0.15.0 (the manifest API) and pays
// for the two uploads, so it runs only when named, never under "all".

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
            case "9", "pointers":
                try await runPointers()
            case "all":
                // Not the pointers example: it pays for every write and needs
                // a fresh owner each run, so it runs only when named.
                try await runData()
                try await runExternalSigner()
            case "10", "manifests":
                try await runManifests()
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

        let fileFin = try await finalizeWithRetry(uploadId: filePrep.uploadId) {
            try await client.finalizeUpload(uploadId: filePrep.uploadId, txHashes: fileTxHashes)
        }
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

    // MARK: - Example 09: Pointers -----------------------------------------
    //
    // A pointer is an owner-signed, mutable reference whose address never
    // changes. antd signs with the owner keys it loaded at startup
    // (`antd --pointer-keys`), so this example names the pointer by its
    // address: set ANTD_POINTER_OWNER to a pointer address the daemon holds a
    // key for (`pointerKeys()` lists them) and that has never been written.
    // ANTD_BASE_URL overrides the daemon URL (default http://localhost:8082).
    //
    // Every pointer write pays (about the price of one chunk) and every
    // attempt pays again, so nothing here retries a write.

    static func runPointers() async throws {
        print("=== Example 09: Pointers ===")
        let env = ProcessInfo.processInfo.environment
        guard let owner = env["ANTD_POINTER_OWNER"], !owner.isEmpty else {
            throw AntdError("set ANTD_POINTER_OWNER to a never-written pointer address the daemon holds a key for")
        }
        let client = AntdClient.createRest(baseURL: env["ANTD_BASE_URL"] ?? "http://localhost:8082")

        // The daemon must hold the owner's key to sign the writes.
        let keys = try await client.pointerKeys()
        guard keys.contains(where: { sameAddress($0.address, owner) }) else {
            throw AntdError("the daemon holds no key for \(owner); it holds \(keys.count) pointer key(s)")
        }

        // 1. Two small pieces of public data to point at.
        let first = try await client.dataPutPublic(Data("pointer target one, from swift".utf8), paymentMode: .auto)
        let second = try await client.dataPutPublic(Data("pointer target two, from swift".utf8), paymentMode: .auto)
        print("Stored targets: \(first.address) and \(second.address)")

        // 2. Create the pointer at the first. Pays once; an AlreadyExistsError
        //    means this owner was written before, so pick a fresh one.
        let created = try await client.pointerCreate(owner: owner, target: first.address, kind: .chunk)
        print("Created pointer \(created.address) at counter \(created.counter)")

        // 3. Point it at the second. Pays again.
        let updated = try await client.pointerUpdate(owner: owner, target: second.address, kind: .chunk)
        print("Updated pointer to counter \(updated.counter)")

        // 4. Read it back, and follow it to the bytes it points at.
        let record = try await client.pointerGet(address: owner)
        print("Pointer record: counter=\(record.counter), kind=\(record.kind), target=\(record.target), final=\(record.isFinal)")
        let resolved = try await client.pointerResolve(address: owner)
        guard sameAddress(resolved.target, second.address) else {
            throw AntdError("pointer resolves to \(resolved.target), expected \(second.address)")
        }
        let data = try await client.dataGetPublic(address: resolved.target)
        print("Resolved to \(resolved.target): \(String(decoding: data, as: UTF8.self))")

        // 5. Where the pointer stands, as its whole close group sees it.
        let finality = try await client.pointerFinality(address: owner)
        let counter = finality.counter.map(String.init) ?? "none"
        print("Finality: \(finality.status.wire) (\(finality.answered)/\(finality.group) peers answered, counter \(counter))")

        print("\n09_pointers OK!\n")
    }

    /// The daemon accepts a `0x` prefix on addresses but always returns bare
    /// hex, so compare them without it.
    static func sameAddress(_ a: String, _ b: String) -> Bool {
        func bare(_ s: String) -> String {
            let lower = s.lowercased()
            return lower.hasPrefix("0x") ? String(lower.dropFirst(2)) : lower
        }
        return bare(a) == bare(b)
    }

    /// Bounded same-payment retry around a finalize call (`finalizeUpload`
    /// or `finalizeMerkleUpload`; `finalize` must repeat the call with the
    /// same `uploadId` and payment artefacts every time).
    ///
    /// A finalize that stored some chunks but not all throws
    /// `PartialUploadError`. Whenever this helper stops, it rethrows that
    /// original error, so the caller keeps its type, counts and flags:
    ///
    /// - `retryable` (antd >= 0.14.0): the daemon kept the paid attempt under
    ///   the same upload_id, so repeating the same finalize stores the
    ///   remainder against the same payment — no re-prepare, no second
    ///   signature, no double payment. A persistent failure (a chunk whose
    ///   close group stays unreachable) throws `PartialUploadError` on every
    ///   call, so this caps the attempts and treats a `chunksFailed` that
    ///   stops shrinking as stuck; the paid attempt is still retained then.
    /// - `retentionKnown && !retryable`: the daemon confirmed it kept nothing.
    ///   Rethrown at once; the caller re-prepares the same content, which
    ///   skips the chunks already stored.
    /// - `!retentionKnown`: retention is unknown and the daemon may still
    ///   hold the paid attempt. Over gRPC this includes a status message
    ///   whose counts read but whose closing retention hint is missing or
    ///   cut short. Rethrown at once: this helper never re-prepares or pays,
    ///   and the caller must keep the upload_id and payment artefacts and
    ///   reconcile before re-preparing or paying again.
    ///
    /// Any other error propagates untouched on the first failure.
    static func finalizeWithRetry<T>(
        uploadId: String,
        maxAttempts: Int = 5,
        backoff: (Int) async throws -> Void = { attempt in
            try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
        },
        finalize: () async throws -> T
    ) async throws -> T {
        var lastFailed: UInt64 = 0
        var attempt = 1
        while true {
            do {
                return try await finalize()
            } catch let partial as PartialUploadError {
                guard partial.retryable else {
                    print(nonRetryableAdvice(partial, uploadId: uploadId))
                    throw partial
                }
                let stuck = attempt > 1 && partial.chunksFailed >= lastFailed
                if attempt >= maxAttempts || stuck {
                    print("finalize stuck after \(attempt) attempt(s): \(partial.chunksStored)/\(partial.totalChunks) chunks stored, \(partial.chunksFailed) still unstored; the paid attempt is retained under upload_id \(uploadId) — resume later with the same arguments")
                    throw partial
                }
                lastFailed = partial.chunksFailed
                print("finalize stored \(partial.chunksStored)/\(partial.totalChunks) chunks, \(partial.chunksFailed) still unstored — retrying against the same payment (attempt \(attempt + 1)/\(maxAttempts))")
                try await backoff(attempt)
                attempt += 1
            }
        }
    }

    /// The advice `finalizeWithRetry` prints when it stops on a
    /// non-retryable `PartialUploadError`. Re-preparing is advised only when
    /// the daemon confirmed it kept nothing (`retentionKnown`); unknown
    /// retention always gets "stop and reconcile".
    static func nonRetryableAdvice(_ partial: PartialUploadError, uploadId: String) -> String {
        if partial.retentionKnown {
            return "finalize stored \(partial.chunksStored)/\(partial.totalChunks) chunks; the daemon kept nothing for upload_id \(uploadId) — re-prepare the same content to store the remainder"
        }
        return "finalize stored \(partial.chunksStored)/\(partial.totalChunks) chunks; retention unknown for upload_id \(uploadId) — stopping: keep the upload_id and payment artefacts and reconcile before re-preparing or paying again"
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

    // MARK: - Example 10: Manifests -----------------------------------------
    //
    // A manifest (ADR-0006) describes a set of files: each entry has a path
    // and either a public DataMap address or an embedded DataMap. Building
    // and decoding one is free: nothing is uploaded or paid for. Only the two
    // uploads below pay. ANTD_BASE_URL overrides the daemon URL (default
    // http://localhost:8082).

    static func runManifests() async throws {
        print("=== Example 10: Manifests ===")
        let env = ProcessInfo.processInfo.environment
        let client = AntdClient.createRest(baseURL: env["ANTD_BASE_URL"] ?? "http://localhost:8082")

        // 1. Two small pieces of public data. Each upload pays.
        let one = Data("manifest entry one, from swift".utf8)
        let two = Data("manifest entry two, from swift, a little longer".utf8)
        let first = try await client.dataPutPublic(one, paymentMode: .auto)
        let second = try await client.dataPutPublic(two, paymentMode: .auto)
        print("Stored: \(first.address) and \(second.address)")

        // 2. A manifest of both, under paths, with a root name. Free.
        let built = try await client.buildManifest(
            entries: [
                ManifestEntryInput(path: "notes/one.txt", address: first.address),
                ManifestEntryInput(path: "notes/two.txt", address: second.address),
            ],
            options: BuildManifestOptions(name: "example")
        )
        print("Manifest: \(built.manifest.count) bytes")
        guard let link = built.link else {
            throw AntdError("a two-entry manifest should fit in a link")
        }
        print("Link: \(link)")
        for entry in built.entries {
            print("  \(entry.effectiveName) -> \(entry.contentAddress)")
        }

        // 3. Decode the link, resolving each entry's DataMap for its exact
        //    size. Free; content chunks are not fetched.
        let decoded = try await client.decodeManifestLink(link, resolve: true)
        print("Decoded \(decoded.source) \"\(decoded.name ?? "")\" with \(decoded.entries.count) entries:")
        let expected = ["notes/one.txt": UInt64(one.count), "notes/two.txt": UInt64(two.count)]
        for entry in decoded.entries {
            if let error = entry.error {
                throw AntdError("\(entry.effectiveName) did not resolve: \(error)")
            }
            let size = entry.exactSize.map(String.init) ?? "unknown"
            print("  \(entry.effectiveName): exact size \(size)")
            guard entry.exactSize == expected[entry.effectiveName] else {
                throw AntdError("\(entry.effectiveName): exact size \(size), expected \(expected[entry.effectiveName].map(String.init) ?? "no entry")")
            }
        }

        print("\n10_manifests OK!\n")
    }
}
