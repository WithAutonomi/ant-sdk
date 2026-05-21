using System.Numerics;
using System.Security.Cryptography;
using System.Text;
using Antd.Sdk;
using Nethereum.ABI.FunctionEncoding.Attributes;

namespace Antd.Examples;

class Program
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
            case "all":
                await Example01_Connect();
                await Example02_Data();
                await Example03_Chunks();
                await Example04_Files();
                await Example06_PrivateData();
                await Example07_ExternalSigner();
                break;
            default:
                Console.WriteLine($"Unknown example: {example}. Use 1-7 or 'all'.");
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
    /// See docs/external-signer-flow.md for the full reference; the
    /// IPaymentVault contract ABI is loaded from docs/abi/IPaymentVault.json.
    /// </summary>
    static async Task Example07_ExternalSigner()
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
            var fileFin = await client.FinalizeUploadAsync(filePrep.UploadId, fileTxHashes);
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
                    $"address={chunkPrep.Address}, payments={chunkPrep.Payments.Count}, " +
                    $"total_amount={chunkPrep.TotalAmount}");

                var chunkTxHashes = await ExternalSignerPayAsync(new PrepareUploadResult(
                    chunkPrep.UploadId, chunkPrep.Payments, chunkPrep.TotalAmount,
                    chunkPrep.PaymentVaultAddress, chunkPrep.PaymentTokenAddress,
                    chunkPrep.RpcUrl, chunkPrep.PaymentType));
                var addr = await client.FinalizeChunkUploadAsync(chunkPrep.UploadId, chunkTxHashes);
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
