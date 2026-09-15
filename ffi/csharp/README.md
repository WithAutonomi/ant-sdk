# Antd.Ffi — direct-network .NET client for Autonomi

.NET 8 bindings over the [`ant-ffi`](https://github.com/WithAutonomi/ant-sdk/tree/main/ffi/rust/ant-ffi) Rust crate, generated with [uniffi-bindgen-cs](https://github.com/NordSecurity/uniffi-bindgen-cs). The client joins the Autonomi network directly: no daemon, no HTTP hop. The native library is bundled in the package for win-x64, win-arm64, linux-x64, linux-arm64, osx-x64 and osx-arm64 and selected automatically at restore time.

For the daemon-backed client (the recommended path for most apps: the daemon holds the wallet and does the networking) see [`Antd.Sdk`](https://www.nuget.org/packages/Antd.Sdk).

## Installation

```bash
dotnet add package Antd.Ffi
```

## Quick start

```csharp
using AntFfi;

Console.WriteLine(AntFfiMethods.AntFfiVersion());

// Offline: derive the EVM address for a wallet key (no RPC contacted).
var wallet = Wallet.FromPrivateKey(
    "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
    "http://localhost:8545",
    "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    "0x5FbDB2315678afecb367f032d93F642f64180aa3");
Console.WriteLine(wallet.Address());

// Online: connect to a local devnet from its manifest and round-trip data.
var client = await Client.ConnectFromDevnetManifest("/path/to/devnet-manifest.json");
var put = await client.DataPutPublic(System.Text.Encoding.UTF8.GetBytes("hello"), PaymentMode.Auto);
var got = await client.DataGetPublic(put.address);
```

The surface mirrors the Python (`ant-sdk`) and Node (`@withautonomi/ant-sdk`) bindings: `Client` (connect variants, data/file/chunk put and get, cost estimates, external-signer prepare/finalize, progress listeners), `Wallet`, and typed records/enums. All `Client` methods are `async` (`Task<T>`), bridged onto the crate's tokio runtime.

## Compatibility

Targets .NET 8. Package version tracks the ant-ffi crate version (`AntFfiMethods.AntFfiVersion()` returns it). Linux builds are made against glibc 2.28 (manylinux_2_28), so any distribution from roughly 2019 on works. Not for browsers or Blazor WebAssembly: direct networking needs a native process.

## Building from source

See [`ffi/README.md`](https://github.com/WithAutonomi/ant-sdk/tree/main/ffi#readme): `ffi/scripts/build.sh` builds the crate, generates `AntFfi/Generated/`, and builds this solution. `dotnet test` runs offline smoke tests (version + wallet derivation); the devnet round-trip is exercised by the publish workflow's smoke consumer.
