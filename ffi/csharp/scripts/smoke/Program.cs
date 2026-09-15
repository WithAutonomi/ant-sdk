// Smoke consumer for the packed Autonomi.Ffi .nupkg (run by publish-nuget-ffi.yml
// on Linux, Windows and macOS). Proves the package resolves, the RID-specific
// native library loads, and an offline crypto call round-trips through the FFI.
using AntFfi;

var version = AntFfiMethods.AntFfiVersion();
var expected = Environment.GetEnvironmentVariable("EXPECTED_VERSION");
if (!string.IsNullOrEmpty(expected) && version != expected)
{
    Console.Error.WriteLine($"native reports {version}, expected {expected}");
    return 1;
}

var wallet = Wallet.FromPrivateKey(
    "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
    "http://localhost:8545",
    "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    "0x5FbDB2315678afecb367f032d93F642f64180aa3");
var address = wallet.Address();
if (!string.Equals(address, "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266", StringComparison.OrdinalIgnoreCase))
{
    Console.Error.WriteLine($"wallet address mismatch: {address}");
    return 1;
}

Console.WriteLine($"Autonomi.Ffi {version} on {System.Runtime.InteropServices.RuntimeInformation.RuntimeIdentifier}: native loaded, wallet {address} OK");
return 0;
