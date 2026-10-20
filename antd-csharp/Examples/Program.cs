using System.Numerics;
using System.Security.Cryptography;
using System.Text;
using Antd.Sdk;
using Nethereum.ABI.FunctionEncoding.Attributes;

namespace Antd.Examples;

partial class Program
{
    static async Task Main(string[] args)
    {
        var example = args.Length > 0 ? args[0] : "all";

        switch (example)
        {
            case "1": await Example01_Connect(); break;
            case "2": await Example02_Data(); break;
            case "3": await Example03_Chunks(); break;
            case "4": await Example04_Files(); break;
            case "6": await Example06_PrivateData(); break;
            case "7": await Example07_ExternalSigner(); break;
            // Not part of "all": every pointer write pays, and a create needs
            // an owner that has never been written.
            case "8" or "pointers": await Example08_Pointers(); break;
            case "all":
                await Example01_Connect();
                await Example02_Data();
                await Example03_Chunks();
                await Example04_Files();
                await Example06_PrivateData();
                await Example07_ExternalSigner();
                break;
            // Not part of "all": it needs antd 0.16.0 or later.
            case "9" or "manifests": await Example09_Manifests(); break;
            default:
                Console.WriteLine($"Unknown example: {example}. Use 1-9, 'pointers', 'manifests' or 'all'.");
                break;
        }
    }

    /// <summary>Example 01: Connect to antd daemon and check health.</summary>
    static async Task Example01_Connect()
    {
        Console.WriteLine("=== Example 01: Connect ===");
        using var client = AntdClient.CreateRest();

        var status = await client.HealthAsync();
        Console.WriteLine($"Daemon healthy: {status.Ok}");
        Console.WriteLine($"Network: {status.Network}");

        if (!status.Ok)
            throw new Exception("antd daemon is not healthy");

        Console.WriteLine("Connection OK!\n");
    }

    /// <summary>Example 02: Store and retrieve public data, with cost estimation.</summary>
    static async Task Example02_Data()
    {
        Console.WriteLine("=== Example 02: Public Data ===");
        using var client = AntdClient.CreateRest();

        var payload = Encoding.UTF8.GetBytes("Hello, Autonomi network!");

        // Estimate cost
        var cost = await client.DataCostAsync(payload);
        Console.WriteLine($"Estimated cost: {cost} atto tokens");

        // Store public data
        var result = await client.DataPutPublicAsync(payload);
        Console.WriteLine($"Stored at address: {result.Address}");
        Console.WriteLine($"Chunks: {result.ChunksStored}, mode: {result.PaymentModeUsed}");

        // Retrieve
        var data = await client.DataGetPublicAsync(result.Address);
        var text = Encoding.UTF8.GetString(data);
        Console.WriteLine($"Retrieved: {text}");

        if (!data.SequenceEqual(payload))
            throw new Exception("Round-trip mismatch!");

        Console.WriteLine("Public data round-trip OK!\n");
    }

    /// <summary>Example 03: Store and retrieve raw chunks.</summary>
    static async Task Example03_Chunks()
    {
        Console.WriteLine("=== Example 03: Chunks ===");
        using var client = AntdClient.CreateRest();

        var rawData = Encoding.UTF8.GetBytes("Raw chunk content for direct storage");

        var result = await client.ChunkPutAsync(rawData);
        Console.WriteLine($"Chunk stored at: {result.Address}");
        Console.WriteLine($"Cost: {result.Cost} atto tokens");

        var retrieved = await client.ChunkGetAsync(result.Address);
        Console.WriteLine($"Retrieved {retrieved.Length} bytes");

        if (!retrieved.SequenceEqual(rawData))
            throw new Exception("Chunk round-trip mismatch!");

        Console.WriteLine("Chunk round-trip OK!\n");
    }

    /// <summary>Example 04: Upload and download files.</summary>
    static async Task Example04_Files()
    {
        Console.WriteLine("=== Example 04: Files ===");
        using var client = AntdClient.CreateRest();

        // Create a temporary file
        var srcPath = Path.GetTempFileName();
        await File.WriteAllTextAsync(srcPath, "Hello from a file on Autonomi!");

        try
        {
            // Estimate cost
            var cost = await client.FileCostAsync(srcPath);
            Console.WriteLine($"File upload cost estimate: {cost} atto tokens");

            // Upload
            var result = await client.FilePutPublicAsync(srcPath);
            Console.WriteLine($"File uploaded to: {result.Address}");
            Console.WriteLine($"Storage cost: {result.StorageCostAtto} atto, gas: {result.GasCostWei} wei");
            Console.WriteLine($"Chunks stored: {result.ChunksStored}, payment mode: {result.PaymentModeUsed}");

            // Download to new location
            var destPath = srcPath + ".downloaded";
            await client.FileGetPublicAsync(result.Address, destPath);
            Console.WriteLine($"Downloaded to: {destPath}");

            var content = await File.ReadAllTextAsync(destPath);
            Console.WriteLine($"Content: {content}");
            File.Delete(destPath);
        }
        finally
        {
            File.Delete(srcPath);
        }

        Console.WriteLine("File upload/download OK!\n");
    }

    /// <summary>Example 06: Private (encrypted) data round-trip.</summary>
    static async Task Example06_PrivateData()
    {
        Console.WriteLine("=== Example 06: Private Data ===");
        using var client = AntdClient.CreateRest();

        var secretMessage = Encoding.UTF8.GetBytes("This message is encrypted on the network");

        // Store private data
        var result = await client.DataPutAsync(secretMessage);
        var dataMap = result.DataMap;
        Console.WriteLine($"Data map: {dataMap}");
        Console.WriteLine($"Chunks: {result.ChunksStored}, mode: {result.PaymentModeUsed}");

        // Retrieve and decrypt
        var retrieved = await client.DataGetAsync(dataMap);
        Console.WriteLine($"Decrypted: {Encoding.UTF8.GetString(retrieved)}");

        if (!retrieved.SequenceEqual(secretMessage))
            throw new Exception("Private data round-trip mismatch!");

        Console.WriteLine("Private data round-trip OK!\n");
    }

    /// <summary>
    /// Example 07: External-signer flow — public file + single-chunk publish.
    ///
    /// PR #90 added PrepareUploadPublicAsync / FinalizeUploadAsync and
    /// PrepareChunkUploadAsync / FinalizeChunkUploadAsync so the wallet key
    /// never has to live in the antd daemon. This example uses anvil
    /// deterministic account #0 as the external signer.
    ///
    /// Both finalize calls go through FinalizeRetry.FinalizeWithRetryAsync
    /// (FinalizeRetry.cs), which resumes a partial store against the same
    /// payment only when the daemon retained the paid attempt
    /// (PartialUploadException.Retryable, antd 0.14.0 and later). Otherwise it
    /// stops and rethrows the typed exception without re-preparing or paying:
    /// re-prepare only when RetentionKnown says the daemon kept nothing, and
    /// reconcile first when retention is unknown. The token cancels the
    /// backoff between attempts.
    ///
    /// See docs/external-signer-flow.md for the full reference (section 6
    /// covers the partial-upload retry); the IPaymentVault contract ABI is
    /// loaded from docs/abi/IPaymentVault.json.
    /// </summary>
    static async Task Example07_ExternalSigner(CancellationToken cancellationToken = default)
    {
        Console.WriteLine("=== Example 07: External Signer ===");
        using var client = AntdClient.CreateRest();

        var tmp = Path.Combine(Path.GetTempPath(), $"antd-csharp-07-extsig-{Guid.NewGuid()}");
        Directory.CreateDirectory(tmp);
        try
        {
            // --- 1. file upload via external signer ---------------------
            var srcPath = Path.Combine(tmp, "file.bin");
            // Per-language distinct content avoids "already stored" on a
            // shared anvil between SDK runs.
            var fileContent = Encoding.UTF8.GetBytes(
                string.Concat(Enumerable.Repeat("hello external signer from csharp (file)\n", 16)));
            await File.WriteAllBytesAsync(srcPath, fileContent);

            var filePrep = await client.PrepareUploadPublicAsync(srcPath);
            Console.WriteLine(
                $"File prepare: upload_id={filePrep.UploadId[..16]}..., " +
                $"payment_type={filePrep.PaymentType}, " +
                $"payments={filePrep.Payments.Count}, total_amount={filePrep.TotalAmount}");

            var fileTxHashes = await ExternalSignerPayAsync(filePrep);
            var fileFin = await FinalizeRetry.FinalizeWithRetryAsync(
                filePrep.UploadId, () => client.FinalizeUploadAsync(filePrep.UploadId, fileTxHashes),
                cancellationToken: cancellationToken);
            Console.WriteLine(
                $"File finalize: data_map_address={fileFin.DataMapAddress}, " +
                $"chunks_stored={fileFin.ChunksStored}");

            var dstPath = srcPath + ".downloaded";
            await client.FileGetPublicAsync(fileFin.DataMapAddress, dstPath);
            var downloaded = await File.ReadAllBytesAsync(dstPath);
            if (!downloaded.SequenceEqual(fileContent))
                throw new Exception("file round-trip mismatch");
            Console.WriteLine("File round-trip OK!");

            // --- 2. single-chunk publish via external signer ------------
            var chunkData = Encoding.UTF8.GetBytes(
                string.Concat(Enumerable.Repeat("hello external signer from csharp (chunk)\n", 8)));
            var chunkPrep = await client.PrepareChunkUploadAsync(chunkData);
            if (chunkPrep.AlreadyStored)
            {
                Console.WriteLine($"Chunk prepare: already_stored, address={chunkPrep.Address}");
            }
            else
            {
                Console.WriteLine(
                    $"Chunk prepare: upload_id={chunkPrep.UploadId[..16]}..., " +
                    $"address={chunkPrep.Address}, payments={chunkPrep.Payments?.Count ?? 0}, " +
                    $"total_amount={chunkPrep.TotalAmount}");

                var chunkTxHashes = await ExternalSignerPayAsync(new PrepareUploadResult(
                    chunkPrep.UploadId, chunkPrep.Payments ?? [], chunkPrep.TotalAmount,
                    chunkPrep.PaymentVaultAddress, chunkPrep.PaymentTokenAddress,
                    chunkPrep.RpcUrl, chunkPrep.PaymentType));
                var addr = await FinalizeRetry.FinalizeWithRetryAsync(
                    chunkPrep.UploadId, () => client.FinalizeChunkUploadAsync(chunkPrep.UploadId, chunkTxHashes),
                    cancellationToken: cancellationToken);
                if (addr != chunkPrep.Address)
                    throw new Exception($"chunk address mismatch: {addr} != {chunkPrep.Address}");
                Console.WriteLine($"Chunk finalize: address={addr}");
            }

            var chunkGot = await client.ChunkGetAsync(chunkPrep.Address);
            if (!chunkGot.SequenceEqual(chunkData))
                throw new Exception("chunk round-trip mismatch");
            Console.WriteLine("Chunk round-trip OK!");
        }
        finally
        {
            try { Directory.Delete(tmp, recursive: true); } catch { }
        }

        Console.WriteLine("\n07_external_signer OK!\n");
    }

    /// <summary>
    /// Example 08: Pointers. A pointer is a small, owner-signed, mutable
    /// reference: its address never changes, what it points at can. This
    /// uploads two pieces of public data, points a pointer at the first,
    /// updates it to the second, reads it back and asks the close group
    /// where it stands.
    ///
    /// Needs an antd started with <c>--pointer-keys</c> and a wallet.
    /// <c>ANTD_POINTER_OWNER</c> names the pointer (an address from
    /// <c>GET /v1/pointers/keys</c>); <c>ANTD_BASE_URL</c> overrides the
    /// daemon URL (default http://localhost:8082). Each write below pays,
    /// about the price of one chunk, and is never retried. Run explicitly
    /// (<c>dotnet run -- 8</c>); "all" leaves it out.
    /// </summary>
    static async Task Example08_Pointers()
    {
        Console.WriteLine("=== Example 08: Pointers ===");
        var owner = Environment.GetEnvironmentVariable("ANTD_POINTER_OWNER")?.Trim();
        if (string.IsNullOrEmpty(owner))
        {
            Console.WriteLine("Skipped: set ANTD_POINTER_OWNER to a pointer address the daemon holds a key for.\n");
            return;
        }
        var baseUrl = Environment.GetEnvironmentVariable("ANTD_BASE_URL");
        using var client = string.IsNullOrEmpty(baseUrl) ? AntdClient.CreateRest() : AntdClient.CreateRest(baseUrl);

        // The daemon accepts a 0x prefix but returns bare hex.
        static string Bare(string a) => (a.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? a[2..] : a).ToLowerInvariant();
        if (!(await client.PointerKeysAsync()).Select(Bare).Contains(Bare(owner)))
            throw new Exception($"the daemon holds no key for {owner} (see GET /v1/pointers/keys)");

        // 1. Two small pieces of public data to point at.
        var stamp = DateTime.UtcNow.ToString("O");
        var firstBytes = Encoding.UTF8.GetBytes($"pointer example, first version ({stamp})");
        var secondBytes = Encoding.UTF8.GetBytes($"pointer example, second version ({stamp})");
        var first = await client.DataPutPublicAsync(firstBytes);
        var second = await client.DataPutPublicAsync(secondBytes);
        Console.WriteLine($"Uploaded: first={first.Address}");
        Console.WriteLine($"          second={second.Address}");

        // 2. Create the pointer at the first. A create is refused, before
        // paying, if the pointer exists, so look first: a rerun with the same
        // owner goes straight to the update.
        PointerRecord? existing = null;
        try { existing = await client.PointerGetAsync(owner); }
        catch (NotFoundException) { }
        if (existing is null)
        {
            var created = await client.PointerCreateAsync(owner, first.Address);
            Console.WriteLine($"Created pointer {created.Address} -> first (counter {created.Counter})");
        }
        else
        {
            Console.WriteLine($"Pointer {existing.Address} already exists (counter {existing.Counter}); skipping create");
        }

        // 3. Update it to the second. Throws PointerFinalException if the
        // pointer has been transferred or frozen (usually before paying).
        var updated = await client.PointerUpdateAsync(owner, second.Address);
        Console.WriteLine($"Updated pointer -> second (counter {updated.Counter})");

        // 4. Resolve and read it; fetch the bytes through the pointer.
        var resolved = await client.PointerResolveAsync(owner);
        var record = await client.PointerGetAsync(owner);
        Console.WriteLine($"Resolved: {resolved.Kind} {resolved.Target}");
        Console.WriteLine($"Record: counter={record.Counter}, kind={record.Kind}, final={record.IsFinal}, owner key {record.Owner.Length / 2} bytes");
        var data = await client.DataGetPublicAsync(resolved.Target);
        if (!data.SequenceEqual(secondBytes))
            throw new Exception("the pointer does not resolve to the second version");
        Console.WriteLine($"Fetched through the pointer: \"{Encoding.UTF8.GetString(data)}\"");

        // 5. Ask the whole close group where it stands. "open": the owner
        // can still move it; only a transfer makes it "final".
        var finality = await client.PointerFinalityAsync(owner);
        Console.WriteLine(
            $"Finality: {finality.RawStatus} (counter {finality.Counter?.ToString() ?? "-"}, " +
            $"{finality.Answered}/{finality.Group} peers answered)");

        Console.WriteLine("\n08_pointers OK!\n");
    }

    // Anvil deterministic account #0. Pre-funded with ETH (gas) and antToken
    // (storage payment) by `ant dev start --enable-evm` devnet genesis. Never
    // use this key anywhere except a throw-away local devnet.
    private const string AnvilKey =
        "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

    // Minimal IPaymentVault ABI — only the function called below. See
    // docs/abi/IPaymentVault.json for the full ABI.
    private const string PaymentVaultAbi = @"[{
        ""name"":""payForQuotes"",""type"":""function"",""stateMutability"":""nonpayable"",
        ""inputs"":[{""name"":""payments"",""type"":""tuple[]"",
            ""components"":[
                {""name"":""rewardsAddress"",""type"":""address""},
                {""name"":""amount"",""type"":""uint256""},
                {""name"":""quoteHash"",""type"":""bytes32""}
            ]}],
        ""outputs"":[]
    }]";

    // Minimal ERC-20 ABI — only approve() used here. antToken is a standard
    // ERC-20.
    private const string Erc20Abi = @"[{
        ""name"":""approve"",""type"":""function"",""stateMutability"":""nonpayable"",
        ""inputs"":[
            {""name"":""spender"",""type"":""address""},
            {""name"":""value"",""type"":""uint256""}
        ],
        ""outputs"":[{""type"":""bool""}]
    }]";

    /// <summary>
    /// Run approve + payForQuotes on-chain for a daemon prepare response.
    /// Returns the quote_hash -> tx_hash map the daemon's finalize_* methods
    /// expect. Every entry maps to the same payForQuotes tx because every
    /// quote in the wave is paid in one batched call.
    /// </summary>
    static async Task<Dictionary<string, string>> ExternalSignerPayAsync(PrepareUploadResult prep)
    {
        // No on-chain work when every quoted chunk is already on-network.
        if (prep.Payments.Count == 0)
            return new Dictionary<string, string>();

        var account = new Nethereum.Web3.Accounts.Account(AnvilKey);
        var web3 = new Nethereum.Web3.Web3(account, prep.RpcUrl);

        // approve(vault, MAX) — idempotent and cheap; example uses MAX so
        // subsequent flows in this run skip a fresh approval. Explicit gas
        // bypasses Nethereum's auto-estimate, which can hang against anvil
        // on EIP-1559 chains depending on Nethereum version.
        var maxUint256 = System.Numerics.BigInteger.Pow(2, 256) - 1;
        var gas = new Nethereum.Hex.HexTypes.HexBigInteger(500_000);
        var zero = new Nethereum.Hex.HexTypes.HexBigInteger(0);

        var token = web3.Eth.GetContract(Erc20Abi, prep.PaymentTokenAddress);
        var approve = token.GetFunction("approve");
        var approveTxHash = await approve.SendTransactionAsync(
            account.Address, gas, zero, prep.PaymentVaultAddress, maxUint256);
        var approveRcpt = await web3.TransactionManager.TransactionReceiptService
            .PollForReceiptAsync(approveTxHash);
        if (approveRcpt.Status.Value != 1)
            throw new Exception($"approve reverted: {approveRcpt.TransactionHash}");

        // payForQuotes — one tx covering every quote in this wave.
        var contract = web3.Eth.GetContract(PaymentVaultAbi, prep.PaymentVaultAddress);
        var payForQuotes = contract.GetFunction("payForQuotes");

        var payments = prep.Payments.Select(p => new DataPaymentDto
        {
            RewardsAddress = p.RewardsAddress,
            Amount = BigInteger.Parse(p.Amount),
            QuoteHash = Convert.FromHexString(
                p.QuoteHash.StartsWith("0x") ? p.QuoteHash[2..] : p.QuoteHash),
        }).ToArray();

        // Wrap the payments array as one object so Nethereum's params
        // object[] doesn't unpack the elements into separate function args.
        var payGas = new Nethereum.Hex.HexTypes.HexBigInteger(1_000_000);
        var payTxHash = await payForQuotes.SendTransactionAsync(
            account.Address, payGas, zero, new object[] { payments });
        var payRcpt = await web3.TransactionManager.TransactionReceiptService
            .PollForReceiptAsync(payTxHash);
        if (payRcpt.Status.Value != 1)
            throw new Exception($"payForQuotes reverted: {payRcpt.TransactionHash}");

        // Every quote in this wave was paid in the same call.
        var txHashes = new Dictionary<string, string>(prep.Payments.Count);
        foreach (var p in prep.Payments)
            txHashes[p.QuoteHash] = payRcpt.TransactionHash;
        return txHashes;
    }
}

/// <summary>
/// Strongly-typed payment for IPaymentVault.payForQuotes — Nethereum's ABI
/// tuple encoder requires [Parameter] attributes (anonymous types don't carry
/// them), so we define a small DTO here. Field order matches the contract
/// struct layout: (address, uint256, bytes32).
/// </summary>
public class DataPaymentDto
{
    [Parameter("address", "rewardsAddress", 1)]
    public string RewardsAddress { get; set; } = "";

    [Parameter("uint256", "amount", 2)]
    public BigInteger Amount { get; set; }

    [Parameter("bytes32", "quoteHash", 3)]
    public byte[] QuoteHash { get; set; } = Array.Empty<byte>();
}
