using System.Security.Cryptography;
using System.Text;
using Antd.Sdk;

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
            case "5": await Example05_Pointers(); break;
            case "6": await Example06_Scratchpads(); break;
            case "7": await Example07_Graph(); break;
            case "8": await Example08_Registers(); break;
            case "9": await Example09_Vaults(); break;
            case "10": await Example10_PrivateData(); break;
            case "all":
                await Example01_Connect();
                await Example02_Data();
                await Example03_Chunks();
                await Example04_Files();
                await Example05_Pointers();
                await Example06_Scratchpads();
                await Example07_Graph();
                await Example08_Registers();
                await Example09_Vaults();
                await Example10_PrivateData();
                break;
            default:
                Console.WriteLine($"Unknown example: {example}. Use 1-10 or 'all'.");
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
        Console.WriteLine($"Actual cost: {result.Cost} atto tokens");

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
            var result = await client.FileUploadPublicAsync(srcPath);
            Console.WriteLine($"File uploaded to: {result.Address}");
            Console.WriteLine($"Actual cost: {result.Cost} atto tokens");

            // Download to new location
            var destPath = srcPath + ".downloaded";
            await client.FileDownloadPublicAsync(result.Address, destPath);
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

    /// <summary>Example 05: Create, read, and update mutable pointers.</summary>
    static async Task Example05_Pointers()
    {
        Console.WriteLine("=== Example 05: Pointers ===");
        using var client = AntdClient.CreateRest();

        var secretKey = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLower();

        // Store data to point to
        var dataV1 = await client.DataPutPublicAsync(Encoding.UTF8.GetBytes("version 1"));
        var dataV2 = await client.DataPutPublicAsync(Encoding.UTF8.GetBytes("version 2"));

        // Create pointer to v1
        var targetV1 = new PointerTarget("chunk", dataV1.Address);
        var ptr = await client.PointerCreateAsync(secretKey, targetV1);
        Console.WriteLine($"Pointer created at: {ptr.Address}");

        // Read
        var pointer = await client.PointerGetAsync(ptr.Address);
        Console.WriteLine($"Points to: {pointer.Target.Kind} @ {pointer.Target.Address}");
        Console.WriteLine($"Counter: {pointer.Counter}");

        // Check existence
        var exists = await client.PointerExistsAsync(ptr.Address);
        Console.WriteLine($"Pointer exists: {exists}");

        // Update to v2
        var targetV2 = new PointerTarget("chunk", dataV2.Address);
        await client.PointerUpdateAsync(secretKey, targetV2);
        Console.WriteLine("Pointer updated to v2");

        // Read again
        pointer = await client.PointerGetAsync(ptr.Address);
        Console.WriteLine($"Now points to: {pointer.Target.Address}");

        Console.WriteLine("Pointer CRUD OK!\n");
    }

    /// <summary>Example 06: Create, read, and update versioned scratchpads.</summary>
    static async Task Example06_Scratchpads()
    {
        Console.WriteLine("=== Example 06: Scratchpads ===");
        using var client = AntdClient.CreateRest();

        var secretKey = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLower();

        // Create
        var initialData = Encoding.UTF8.GetBytes("scratchpad v1 data");
        ulong contentType = 1;
        var result = await client.ScratchpadCreateAsync(secretKey, contentType, initialData);
        Console.WriteLine($"Scratchpad created at: {result.Address}");
        Console.WriteLine($"Cost: {result.Cost} atto tokens");

        // Read
        var pad = await client.ScratchpadGetAsync(result.Address);
        Console.WriteLine($"Data encoding: {pad.DataEncoding}");
        Console.WriteLine($"Counter: {pad.Counter}");
        Console.WriteLine($"Data length: {pad.Data.Length} bytes");

        // Check existence
        var exists = await client.ScratchpadExistsAsync(result.Address);
        Console.WriteLine($"Scratchpad exists: {exists}");

        // Update
        var updatedData = Encoding.UTF8.GetBytes("scratchpad v2 data");
        await client.ScratchpadUpdateAsync(secretKey, contentType, updatedData);
        Console.WriteLine("Scratchpad updated");

        // Read again
        pad = await client.ScratchpadGetAsync(result.Address);
        Console.WriteLine($"Counter after update: {pad.Counter}");

        Console.WriteLine("Scratchpad CRUD OK!\n");
    }

    /// <summary>Example 07: Graph entry (DAG node) operations.</summary>
    static async Task Example07_Graph()
    {
        Console.WriteLine("=== Example 07: Graph ===");
        using var client = AntdClient.CreateRest();

        var secretKey = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLower();

        // Create a root graph entry
        var content = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLower();
        var result = await client.GraphEntryPutAsync(
            secretKey,
            new List<string>(),
            content,
            new List<GraphDescendant>()
        );
        Console.WriteLine($"Graph entry created at: {result.Address}");
        Console.WriteLine($"Cost: {result.Cost} atto tokens");

        // Read
        var entry = await client.GraphEntryGetAsync(result.Address);
        Console.WriteLine($"Owner: {entry.Owner}");
        Console.WriteLine($"Content: {entry.Content}");
        Console.WriteLine($"Parents: {entry.Parents.Count}");
        Console.WriteLine($"Descendants: {entry.Descendants.Count}");

        // Check existence
        var exists = await client.GraphEntryExistsAsync(result.Address);
        Console.WriteLine($"Graph entry exists: {exists}");

        // Estimate cost
        var cost = await client.GraphEntryCostAsync(secretKey);
        Console.WriteLine($"Cost estimate for new entry: {cost} atto tokens");

        Console.WriteLine("Graph entry operations OK!\n");
    }

    /// <summary>Example 08: Register create, read, and update.</summary>
    static async Task Example08_Registers()
    {
        Console.WriteLine("=== Example 08: Registers ===");
        using var client = AntdClient.CreateRest();

        var secretKey = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLower();

        // Create with initial value (32 zero bytes)
        var initialValue = new string('0', 64);
        var result = await client.RegisterCreateAsync(secretKey, initialValue);
        Console.WriteLine($"Register created at: {result.Address}");
        Console.WriteLine($"Cost: {result.Cost} atto tokens");

        // Read
        var reg = await client.RegisterGetAsync(result.Address);
        Console.WriteLine($"Current value: {reg.Value}");

        // Update
        var newValue = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLower();
        var updateResult = await client.RegisterUpdateAsync(secretKey, newValue);
        Console.WriteLine($"Update cost: {updateResult.Cost} atto tokens");

        // Read again
        reg = await client.RegisterGetAsync(result.Address);
        Console.WriteLine($"Updated value: {reg.Value}");

        Console.WriteLine("Register CRUD OK!\n");
    }

    /// <summary>Example 09: Vault store and retrieve.</summary>
    static async Task Example09_Vaults()
    {
        Console.WriteLine("=== Example 09: Vaults ===");
        using var client = AntdClient.CreateRest();

        var secretKey = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLower();

        // Store
        var payload = Encoding.UTF8.GetBytes("Secret vault data that is encrypted");
        ulong contentType = 42;
        var cost = await client.VaultPutAsync(secretKey, payload, contentType);
        Console.WriteLine($"Vault store cost: {cost} atto tokens");

        // Retrieve
        var vault = await client.VaultGetAsync(secretKey);
        Console.WriteLine($"Content type: {vault.ContentType}");
        Console.WriteLine($"Data: {Encoding.UTF8.GetString(vault.Data)}");

        if (!vault.Data.SequenceEqual(payload))
            throw new Exception("Vault round-trip mismatch!");
        if (vault.ContentType != contentType)
            throw new Exception("Content type mismatch!");

        Console.WriteLine("Vault round-trip OK!\n");
    }

    /// <summary>Example 10: Private (encrypted) data round-trip.</summary>
    static async Task Example10_PrivateData()
    {
        Console.WriteLine("=== Example 10: Private Data ===");
        using var client = AntdClient.CreateRest();

        var secretMessage = Encoding.UTF8.GetBytes("This message is encrypted on the network");

        // Store private data
        var result = await client.DataPutPrivateAsync(secretMessage);
        var dataMap = result.Address; // for private data, address holds the data map
        Console.WriteLine($"Data map: {dataMap}");
        Console.WriteLine($"Cost: {result.Cost} atto tokens");

        // Retrieve and decrypt
        var retrieved = await client.DataGetPrivateAsync(dataMap);
        Console.WriteLine($"Decrypted: {Encoding.UTF8.GetString(retrieved)}");

        if (!retrieved.SequenceEqual(secretMessage))
            throw new Exception("Private data round-trip mismatch!");

        Console.WriteLine("Private data round-trip OK!\n");
    }
}
