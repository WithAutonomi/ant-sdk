using System.Runtime.InteropServices;
using Antd.Sdk;

namespace Antd.Sdk.Tests;

public class TestRunner
{
    private readonly IAntdClient _client;
    private readonly string _transport;
    private readonly List<(string Name, string Status)> _results = [];

    private static readonly bool AnsiSupported = EnableAnsi();
    private static readonly string Green = AnsiSupported ? "\x1b[92m" : "";
    private static readonly string Red = AnsiSupported ? "\x1b[91m" : "";
    private static readonly string Yellow = AnsiSupported ? "\x1b[93m" : "";
    private static readonly string Cyan = AnsiSupported ? "\x1b[96m" : "";
    private static readonly string Bold = AnsiSupported ? "\x1b[1m" : "";
    private static readonly string Reset = AnsiSupported ? "\x1b[0m" : "";

    private static bool EnableAnsi()
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            return true;
        try
        {
            var handle = GetStdHandle(-11); // STD_OUTPUT_HANDLE
            if (GetConsoleMode(handle, out uint mode))
            {
                mode |= 0x0004; // ENABLE_VIRTUAL_TERMINAL_PROCESSING
                SetConsoleMode(handle, mode);
                return true;
            }
        }
        catch { }
        return false;
    }

    [DllImport("kernel32.dll")] private static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll")] private static extern bool GetConsoleMode(IntPtr handle, out uint mode);
    [DllImport("kernel32.dll")] private static extern bool SetConsoleMode(IntPtr handle, uint mode);

    private const int PropagationDelay = 3;

    // Unique keys per transport to avoid DHT collisions between REST and gRPC runs
    private readonly string _keyGraph;

    public TestRunner(IAntdClient client, string transport)
    {
        _client = client;
        _transport = transport;

        // Offset keys by transport: REST uses 01-04, gRPC uses 11-14
        var offset = transport == "grpc" ? "1" : "0";
        _keyGraph      = new string('0', 62) + offset + "3";
    }

    private void Pass(string name, string detail = "")
    {
        _results.Add((name, "PASS"));
        Console.WriteLine($"  {Green}PASS{Reset}  {name}" + (detail.Length > 0 ? $"  ({detail})" : ""));
    }

    private void Fail(string name, string detail = "")
    {
        _results.Add((name, "FAIL"));
        Console.WriteLine($"  {Red}FAIL{Reset}  {name}" + (detail.Length > 0 ? $"  ({detail})" : ""));
    }

    private void Skip(string name, string detail = "")
    {
        _results.Add((name, "SKIP"));
        Console.WriteLine($"  {Yellow}SKIP{Reset}  {name}" + (detail.Length > 0 ? $"  ({detail})" : ""));
    }

    public async Task<int> RunAllAsync()
    {
        var endpointDesc = _transport == "grpc" ? "localhost:50051" : "localhost:8080";
        Console.WriteLine($"\n{Bold}{Cyan}antd C# SDK - {_transport.ToUpperInvariant()} Integration Test{Reset}");
        Console.WriteLine($"Target: {endpointDesc}\n");

        await TestHealth();
        var dataAddr = await TestDataPublic();
        await TestDataCost();
        var chunkAddr = await TestChunks();
        await TestGraph();
        await TestLargeData();

        // Summary
        Console.WriteLine();
        var passed = _results.Count(r => r.Status == "PASS");
        var failed = _results.Count(r => r.Status == "FAIL");
        var skipped = _results.Count(r => r.Status == "SKIP");
        var total = _results.Count;

        var color = failed == 0 ? Green : Red;
        Console.Write($"{Bold}Results: {color}{passed}/{total} passed{Reset}");
        if (failed > 0) Console.Write($", {Red}{failed} failed{Reset}");
        if (skipped > 0) Console.Write($", {Yellow}{skipped} skipped{Reset}");
        Console.WriteLine();

        return failed > 0 ? 1 : 0;
    }

    // 1. Health
    private async Task TestHealth()
    {
        try
        {
            var status = await _client.HealthAsync();
            if (status.Ok) Pass($"Health check (network={status.Network})");
            else
            {
                Fail("Health check");
                Console.WriteLine($"\n{Red}Cannot reach antd. Is it running?{Reset}");
            }
        }
        catch (Exception ex)
        {
            Fail("Health check", ex.Message);
            Console.WriteLine($"\n{Red}Cannot reach antd. Is it running?{Reset}");
        }
    }

    // 2. Public data put/get round-trip
    private async Task<string?> TestDataPublic()
    {
        string? dataAddr = null;
        try
        {
            var testData = System.Text.Encoding.UTF8.GetBytes("hello from C# SDK!");
            var result = await _client.DataPutPublicAsync(testData);
            dataAddr = result.Address;
            Pass("Data put public", $"addr={result.Address[..16]}... cost={result.Cost}");
        }
        catch (Exception ex)
        {
            Fail("Data put public", ex.Message);
        }

        if (dataAddr != null)
        {
            try
            {
                var got = await _client.DataGetPublicAsync(dataAddr);
                var text = System.Text.Encoding.UTF8.GetString(got);
                if (text == "hello from C# SDK!")
                    Pass("Data get public", $"{got.Length} bytes");
                else
                    Fail("Data get public", $"data mismatch: got {got.Length} bytes");
            }
            catch (Exception ex) { Fail("Data get public", ex.Message); }
        }
        else
        {
            Skip("Data get public", "no address from put");
        }

        return dataAddr;
    }

    // 3. Data cost estimation
    private async Task TestDataCost()
    {
        try
        {
            var cost = await _client.DataCostAsync(System.Text.Encoding.UTF8.GetBytes("cost estimation test data"));
            Pass("Data cost", $"cost={cost}");
        }
        catch (Exception ex) { Fail("Data cost", ex.Message); }
    }

    // 4. Chunk put/get round-trip
    private async Task<string?> TestChunks()
    {
        string? chunkAddr = null;
        try
        {
            var chunkData = System.Text.Encoding.UTF8.GetBytes("chunk test payload from C#");
            var result = await _client.ChunkPutAsync(chunkData);
            chunkAddr = result.Address;
            Pass("Chunk put", $"addr={result.Address[..16]}... cost={result.Cost}");
        }
        catch (Exception ex) { Fail("Chunk put", ex.Message); }

        if (chunkAddr != null)
        {
            try
            {
                var got = await _client.ChunkGetAsync(chunkAddr);
                var text = System.Text.Encoding.UTF8.GetString(got);
                if (text == "chunk test payload from C#")
                    Pass("Chunk get", $"{got.Length} bytes");
                else
                    Fail("Chunk get", "data mismatch");
            }
            catch (Exception ex) { Fail("Chunk get", ex.Message); }
        }
        else
        {
            Skip("Chunk get", "no address from put");
        }

        return chunkAddr;
    }

    // 5. Graph entry put/exists/get/cost
    private async Task TestGraph()
    {
        string? graphAddr = null;
        try
        {
            var contentHex = string.Concat(Enumerable.Repeat("ab", 32)); // "abab...ab" 64 hex chars = 32 bytes
            var result = await _client.GraphEntryPutAsync(_keyGraph, [], contentHex, []);
            graphAddr = result.Address;
            Pass("Graph entry put", $"addr={result.Address[..16]}... cost={result.Cost}");
        }
        catch (AlreadyExistsException)
        {
            Pass("Graph entry put", "already exists (expected on re-run)");
        }
        catch (Exception ex) { Fail("Graph entry put", ex.Message); }

        if (graphAddr != null)
        {
            Console.WriteLine($"  ... waiting {PropagationDelay}s for DHT propagation");
            await Task.Delay(PropagationDelay * 1000);

            try
            {
                var exists = await _client.GraphEntryExistsAsync(graphAddr);
                if (exists) Pass("Graph entry exists");
                else Fail("Graph entry exists", "returned false");
            }
            catch (Exception ex) { Fail("Graph entry exists", ex.Message); }

            try
            {
                var entry = await _client.GraphEntryGetAsync(graphAddr);
                Pass("Graph entry get", $"owner={entry.Owner[..16]}... content={entry.Content[..16]}...");
            }
            catch (Exception ex) { Fail("Graph entry get", ex.Message); }

            try
            {
                var cost = await _client.GraphEntryCostAsync(graphAddr);
                Pass("Graph entry cost", $"cost={cost}");
            }
            catch (Exception ex) { Fail("Graph entry cost", ex.Message); }
        }
        else
        {
            Skip("Graph entry exists", "no graph address");
            Skip("Graph entry get", "no graph address");
            Skip("Graph entry cost", "no graph address");
        }
    }

    // 6. Large data round-trip (10 KB)
    private async Task TestLargeData()
    {
        try
        {
            var largeData = new byte[10 * 1024];
            Random.Shared.NextBytes(largeData);
            var result = await _client.DataPutPublicAsync(largeData);
            var got = await _client.DataGetPublicAsync(result.Address);
            if (got.SequenceEqual(largeData))
                Pass("Large data round-trip (10KB)", $"addr={result.Address[..16]}...");
            else
                Fail("Large data round-trip (10KB)", $"data mismatch: sent {largeData.Length}, got {got.Length}");
        }
        catch (Exception ex) { Fail("Large data round-trip (10KB)", ex.Message); }
    }
}
