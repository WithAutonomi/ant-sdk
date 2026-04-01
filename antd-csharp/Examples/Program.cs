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
            case "6": await Example06_PrivateData(); break;
            case "all":
                await Example01_Connect();
                await Example02_Data();
                await Example03_Chunks();
                await Example04_Files();
                await Example06_PrivateData();
                break;
            default:
                Console.WriteLine($"Unknown example: {example}. Use 1-6 or 'all'.");
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

    /// <summary>Example 06: Private (encrypted) data round-trip.</summary>
    static async Task Example06_PrivateData()
    {
        Console.WriteLine("=== Example 06: Private Data ===");
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
