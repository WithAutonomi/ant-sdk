# Tutorial: Build a Key-Value Store

This tutorial shows how to build a simple key-value store on the Autonomi network using **registers** for fixed-size values and **pointers** for arbitrary-size values.

## Concepts

- **Registers**: 32-byte mutable values. Fast to read/write, but limited to exactly 32 bytes (64 hex chars).
- **Pointers**: Mutable references to any resource. Point to immutable data chunks of any size.

**Strategy**:
- For values that fit in 32 bytes (hashes, IDs, counters): use registers directly.
- For larger values: store the value as immutable data, then use a pointer to track the latest version.

## Prerequisites

- antd daemon running (`ant dev start`)
- Python SDK: `pip install antd[rest]`
- Or C# SDK built: `dotnet build`

## Part 1: Register-Based KV Store (32-byte values)

Each "key" is a secret key that derives a deterministic network address.

### Python

```python
import hashlib
import os
from antd import AntdClient

client = AntdClient()


def key_to_secret(name: str) -> str:
    """Derive a deterministic secret key from a human-readable name."""
    return hashlib.sha256(f"kv-store:{name}".encode()).hexdigest()


def put(name: str, value: str) -> str:
    """Store a 32-byte hex value under a name."""
    secret = key_to_secret(name)
    # Pad or truncate to 64 hex chars (32 bytes)
    hex_value = value.ljust(64, "0")[:64]

    try:
        result = client.register_create(secret, hex_value)
        print(f"Created '{name}' at {result.address}")
        return result.address
    except Exception:
        # Already exists — update instead
        result = client.register_update(secret, hex_value)
        print(f"Updated '{name}'")
        return result.address


def get(name: str, address: str) -> str:
    """Read the current value."""
    reg = client.register_get(address)
    return reg.value


# Usage
addr = put("user:alice:status", "online".encode().hex())
value = get("user:alice:status", addr)
print(f"Value (hex): {value}")
print(f"Value (text): {bytes.fromhex(value).decode(errors='replace').rstrip('\\x00')}")
```

### C#

```csharp
using System.Security.Cryptography;
using System.Text;
using Antd.Sdk;

using var client = AntdClient.CreateRest();

string KeyToSecret(string name)
{
    var hash = SHA256.HashData(Encoding.UTF8.GetBytes($"kv-store:{name}"));
    return Convert.ToHexString(hash).ToLower();
}

async Task<string> Put(string name, string hexValue)
{
    var secret = KeyToSecret(name);
    hexValue = hexValue.PadRight(64, '0')[..64];

    try
    {
        var result = await client.RegisterCreateAsync(secret, hexValue);
        Console.WriteLine($"Created '{name}' at {result.Address}");
        return result.Address;
    }
    catch (AlreadyExistsException)
    {
        var result = await client.RegisterUpdateAsync(secret, hexValue);
        Console.WriteLine($"Updated '{name}'");
        return result.Address;
    }
}

async Task<string> Get(string name, string address)
{
    var reg = await client.RegisterGetAsync(address);
    return reg.Value;
}

// Usage
var addr = await Put("user:alice:status", Convert.ToHexString(
    Encoding.UTF8.GetBytes("online")).ToLower());
var value = await Get("user:alice:status", addr);
Console.WriteLine($"Value (hex): {value}");
```

## Part 2: Pointer-Based KV Store (Arbitrary Values)

For values larger than 32 bytes, store the value as immutable data and use a pointer.

### Python

```python
import hashlib
from antd import AntdClient, PointerTarget

client = AntdClient()


def key_to_secret(name: str) -> str:
    return hashlib.sha256(f"kv-pointer:{name}".encode()).hexdigest()


class KVStore:
    """A key-value store backed by Autonomi pointers and immutable data."""

    def __init__(self):
        self._addresses: dict[str, str] = {}  # name -> pointer address

    def put(self, name: str, value: bytes) -> None:
        """Store a value. Creates or updates the pointer."""
        secret = key_to_secret(name)

        # Store the value as immutable data
        data_result = client.data_put_public(value)

        # Create or update the pointer
        target = PointerTarget(kind="chunk", address=data_result.address)

        if name not in self._addresses:
            ptr_result = client.pointer_create(secret, target)
            self._addresses[name] = ptr_result.address
            print(f"Created '{name}' -> {data_result.address[:16]}...")
        else:
            client.pointer_update(secret, target)
            print(f"Updated '{name}' -> {data_result.address[:16]}...")

    def get(self, name: str) -> bytes | None:
        """Retrieve the current value."""
        addr = self._addresses.get(name)
        if not addr:
            return None

        pointer = client.pointer_get(addr)
        return client.data_get_public(pointer.target.address)

    def version(self, name: str) -> int:
        """Get the current version counter."""
        addr = self._addresses.get(name)
        if not addr:
            return -1
        pointer = client.pointer_get(addr)
        return pointer.counter


# Usage
store = KVStore()

# Store a JSON config
import json
config = json.dumps({"theme": "dark", "lang": "en", "notifications": True})
store.put("app:config", config.encode())

# Read it back
data = store.get("app:config")
print(f"Config: {json.loads(data)}")
print(f"Version: {store.version('app:config')}")

# Update it
new_config = json.dumps({"theme": "light", "lang": "en", "notifications": False})
store.put("app:config", new_config.encode())

data = store.get("app:config")
print(f"Updated: {json.loads(data)}")
print(f"Version: {store.version('app:config')}")
```

### C#

```csharp
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Antd.Sdk;

using var client = AntdClient.CreateRest();

string KeyToSecret(string name)
{
    var hash = SHA256.HashData(Encoding.UTF8.GetBytes($"kv-pointer:{name}"));
    return Convert.ToHexString(hash).ToLower();
}

var addresses = new Dictionary<string, string>();

async Task Put(string name, byte[] value)
{
    var secret = KeyToSecret(name);
    var dataResult = await client.DataPutPublicAsync(value);
    var target = new PointerTarget("chunk", dataResult.Address);

    if (!addresses.ContainsKey(name))
    {
        var ptrResult = await client.PointerCreateAsync(secret, target);
        addresses[name] = ptrResult.Address;
        Console.WriteLine($"Created '{name}'");
    }
    else
    {
        await client.PointerUpdateAsync(secret, target);
        Console.WriteLine($"Updated '{name}'");
    }
}

async Task<byte[]?> Get(string name)
{
    if (!addresses.TryGetValue(name, out var addr)) return null;
    var pointer = await client.PointerGetAsync(addr);
    return await client.DataGetPublicAsync(pointer.Target.Address);
}

// Usage
var config = JsonSerializer.Serialize(new { theme = "dark", lang = "en" });
await Put("app:config", Encoding.UTF8.GetBytes(config));

var data = await Get("app:config");
Console.WriteLine($"Config: {Encoding.UTF8.GetString(data!)}");
```

## Part 3: Persisting the Address Map

The examples above keep pointer addresses in memory. To make a truly persistent KV store, store the address map itself on the network using a vault:

### Python

```python
import json
from antd import AntdClient

client = AntdClient()

# Your vault secret key — this is your "master key" for the KV store
VAULT_KEY = "your_32_byte_hex_secret_key_here"


def save_index(addresses: dict[str, str]) -> None:
    """Persist the name -> pointer address mapping in a vault."""
    data = json.dumps(addresses).encode()
    client.vault_put(VAULT_KEY, data, content_type=1)


def load_index() -> dict[str, str]:
    """Load the address mapping from the vault."""
    try:
        vault = client.vault_get(VAULT_KEY)
        return json.loads(vault.data)
    except Exception:
        return {}
```

This gives you a fully decentralized key-value store with no central server.

## Next Steps

- [Tutorial: Mutable Configuration](tutorial-mutable-config.md) — Scratchpads for versioned state
- [Architecture Guide](architecture.md) — Understanding the data model
