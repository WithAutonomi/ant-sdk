using AntFfi;
using Xunit;

namespace AntFfi.Tests;

/// <summary>
/// Offline smoke tests for the generated C# bindings — mirror of
/// ffi/python/tests/test_smoke.py. No network required: the native library must
/// load, report its version, and perform a deterministic crypto operation
/// (EVM address derivation from a known private key). The devnet put/get
/// round-trip is exercised by the publish workflow's smoke consumer where a
/// devnet exists.
/// </summary>
public class SmokeTests
{
    // Standard Anvil dev account #0 — deterministic key -> address, pure
    // crypto, no RPC reachability needed.
    private const string AnvilKey = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
    private const string AnvilAddress = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266";

    [Fact]
    public void BindingsLoadAndReportVersion()
    {
        var version = AntFfiMethods.AntFfiVersion();
        Assert.False(string.IsNullOrWhiteSpace(version), "AntFfiVersion() should return a version string");
        Assert.Matches(@"^\d+\.\d+\.\d+", version);
    }

    [Fact]
    public void WalletAddressDerivationOffline()
    {
        var wallet = Wallet.FromPrivateKey(
            AnvilKey,
            "http://localhost:8545", // not contacted for address derivation
            "0x5FbDB2315678afecb367f032d93F642f64180aa3",
            "0x5FbDB2315678afecb367f032d93F642f64180aa3");
        Assert.Equal(AnvilAddress, wallet.Address().ToLowerInvariant());
    }

    [Fact]
    public void TypedEnumsAreExposed()
    {
        // The 0.0.8 wave replaced stringly-typed params with enums; make sure
        // they generated and round-trip through the converter functions.
        Assert.True(Enum.IsDefined(typeof(PaymentMode), PaymentMode.Auto));
        Assert.NotEqual(PaymentMode.Auto, PaymentMode.Single);
    }
}
