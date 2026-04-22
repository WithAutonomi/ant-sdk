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

    public TestRunner(IAntdClient client, string transport)
    {
        _client = client;
        _transport = transport;
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
        var endpointDesc = _transport == "grpc" ? "localhost:50051" : "localhost:8082";
        Console.WriteLine($"\n{Bold}{Cyan}antd C# SDK - {_transport.ToUpperInvariant()} Integration Test{Reset}");
        Console.WriteLine($"Target: {endpointDesc}\n");

        await TestHealth();
        var dataAddr = await TestDataPublic();
        await TestDataCost();
        var chunkAddr = await TestChunks();
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
            var est = await _client.DataCostAsync(System.Text.Encoding.UTF8.GetBytes("cost estimation test data"));
            Pass("Data cost", $"cost={est.Cost} chunks={est.ChunkCount} size={est.FileSize} mode={est.PaymentMode}");
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

    // 5. Large data round-trip (10 KB)
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
