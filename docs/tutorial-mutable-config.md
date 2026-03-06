# Tutorial: Mutable Configuration

This tutorial shows two approaches to managing mutable application configuration on the Autonomi network, with examples in Python, C#, Kotlin, and Swift:

1. **Pointers** — Point to immutable config snapshots. Simple, good for small configs.
2. **Scratchpads** — Versioned mutable storage with built-in counter. Good for frequently-updated state.

## Prerequisites

- antd daemon running (`ant dev start`)
- Python SDK: `pip install antd[rest]`
- Or C# SDK built: `dotnet build`
- Or Kotlin SDK: add `com.autonomi:sdk` dependency via Gradle/Maven
- Or Swift SDK built: `swift build` (macOS only)

## Approach 1: Pointers to Immutable Config

Store each config version as immutable data, then update a pointer to the latest.

### Python

```python
import json
import os
from antd import AntdClient, PointerTarget

client = AntdClient()
secret_key = os.urandom(32).hex()

# Initial config
config_v1 = {
    "app_name": "MyApp",
    "debug": True,
    "max_retries": 3,
    "api_url": "http://localhost:8080",
}

# Store config as immutable data
data_v1 = client.data_put_public(json.dumps(config_v1).encode())
print(f"Config v1 stored at: {data_v1.address}")

# Create a pointer to the current config
target = PointerTarget(kind="chunk", address=data_v1.address)
pointer = client.pointer_create(secret_key, target)
config_address = pointer.address
print(f"Config pointer: {config_address}")

# --- Reading config (anyone can do this) ---
def read_config(pointer_addr: str) -> dict:
    ptr = client.pointer_get(pointer_addr)
    raw = client.data_get_public(ptr.target.address)
    return json.loads(raw)

current = read_config(config_address)
print(f"Current config: {current}")

# --- Updating config (only the owner) ---
config_v2 = {**config_v1, "debug": False, "max_retries": 5}
data_v2 = client.data_put_public(json.dumps(config_v2).encode())
client.pointer_update(secret_key, PointerTarget(kind="chunk", address=data_v2.address))
print("Config updated to v2")

# Verify
current = read_config(config_address)
print(f"Updated config: {current}")
assert current["debug"] is False
assert current["max_retries"] == 5
```

### C#

```csharp
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Antd.Sdk;

using var client = AntdClient.CreateRest();
var secretKey = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLower();

var configV1 = new { app_name = "MyApp", debug = true, max_retries = 3 };
var dataV1 = await client.DataPutPublicAsync(
    Encoding.UTF8.GetBytes(JsonSerializer.Serialize(configV1))
);

var target = new PointerTarget("chunk", dataV1.Address);
var pointer = await client.PointerCreateAsync(secretKey, target);
Console.WriteLine($"Config pointer: {pointer.Address}");

// Read config
async Task<JsonElement> ReadConfig(string pointerAddr)
{
    var ptr = await client.PointerGetAsync(pointerAddr);
    var raw = await client.DataGetPublicAsync(ptr.Target.Address);
    return JsonSerializer.Deserialize<JsonElement>(raw);
}

var current = await ReadConfig(pointer.Address);
Console.WriteLine($"Current: {current}");

// Update
var configV2 = new { app_name = "MyApp", debug = false, max_retries = 5 };
var dataV2 = await client.DataPutPublicAsync(
    Encoding.UTF8.GetBytes(JsonSerializer.Serialize(configV2))
);
await client.PointerUpdateAsync(secretKey, new PointerTarget("chunk", dataV2.Address));
Console.WriteLine("Updated to v2");
```

### Kotlin

```kotlin
import com.autonomi.sdk.AntdClient
import com.autonomi.sdk.PointerTarget
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class AppConfig(
    val appName: String,
    val debug: Boolean,
    val maxRetries: Int,
    val apiUrl: String = "http://localhost:8080",
)

fun main() = runBlocking {
    val client = AntdClient.createRest()
    val secretKey = java.security.SecureRandom().nextBytes(ByteArray(32))
        .joinToString("") { "%02x".format(it) }

    // Initial config
    val configV1 = AppConfig(
        appName = "MyApp",
        debug = true,
        maxRetries = 3,
    )

    // Store config as immutable data
    val dataV1 = client.dataPutPublic(Json.encodeToString(configV1).toByteArray())
    println("Config v1 stored at: ${dataV1.address}")

    // Create a pointer to the current config
    val target = PointerTarget("chunk", dataV1.address)
    val pointer = client.pointerCreate(secretKey, target)
    val configAddress = pointer.address
    println("Config pointer: $configAddress")

    // --- Reading config (anyone can do this) ---
    suspend fun readConfig(pointerAddr: String): AppConfig {
        val ptr = client.pointerGet(pointerAddr)
        val raw = client.dataGetPublic(ptr.target.address)
        return Json.decodeFromString<AppConfig>(String(raw))
    }

    val current = readConfig(configAddress)
    println("Current config: $current")

    // --- Updating config (only the owner) ---
    val configV2 = configV1.copy(debug = false, maxRetries = 5)
    val dataV2 = client.dataPutPublic(Json.encodeToString(configV2).toByteArray())
    client.pointerUpdate(secretKey, PointerTarget("chunk", dataV2.address))
    println("Config updated to v2")

    // Verify
    val updated = readConfig(configAddress)
    println("Updated config: $updated")
    check(!updated.debug)
    check(updated.maxRetries == 5)
}
```

### Swift

```swift
import AntdSdk
import Foundation

let client = try AntdClient.createRest()

var bytes = [UInt8](repeating: 0, count: 32)
_ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
let secretKey = bytes.map { String(format: "%02x", $0) }.joined()

// Initial config
let configV1: [String: Any] = [
    "app_name": "MyApp",
    "debug": true,
    "max_retries": 3,
    "api_url": "http://localhost:8080",
]

// Store config as immutable data
let jsonV1 = try JSONSerialization.data(withJSONObject: configV1)
let dataV1 = try await client.dataPutPublic(jsonV1)
print("Config v1 stored at: \(dataV1.address)")

// Create a pointer to the current config
let target = PointerTarget(kind: "chunk", address: dataV1.address)
let pointer = try await client.pointerCreate(ownerSecretKey: secretKey, target: target)
let configAddress = pointer.address
print("Config pointer: \(configAddress)")

// --- Reading config (anyone can do this) ---
func readConfig(_ pointerAddr: String) async throws -> [String: Any] {
    let ptr = try await client.pointerGet(address: pointerAddr)
    let raw = try await client.dataGetPublic(address: ptr.target.address)
    return try JSONSerialization.jsonObject(with: raw) as! [String: Any]
}

let current = try await readConfig(configAddress)
print("Current config: \(current)")

// --- Updating config (only the owner) ---
let configV2: [String: Any] = [
    "app_name": "MyApp",
    "debug": false,
    "max_retries": 5,
    "api_url": "http://localhost:8080",
]
let jsonV2 = try JSONSerialization.data(withJSONObject: configV2)
let dataV2 = try await client.dataPutPublic(jsonV2)
try await client.pointerUpdate(
    ownerSecretKey: secretKey,
    target: PointerTarget(kind: "chunk", address: dataV2.address)
)
print("Config updated to v2")

let updated = try await readConfig(configAddress)
print("Updated config: \(updated)")
```

**Tradeoffs**:
- Old versions remain on the network (immutable). This is version history for free.
- Each update stores a new complete copy of the config.
- Pointer read is two network operations: read pointer, then read data.

## Approach 2: Scratchpads for Versioned Config

Scratchpads store data directly (no indirection) and include a version counter.

### Python

```python
import json
import os
from antd import AntdClient

client = AntdClient()
secret_key = os.urandom(32).hex()

# Content type constants for our app
CONFIG_TYPE = 1

# Initial config
config = {
    "app_name": "MyApp",
    "features": {"dark_mode": True, "notifications": True},
    "version": "1.0.0",
}

# Create scratchpad with initial config
result = client.scratchpad_create(
    secret_key,
    content_type=CONFIG_TYPE,
    data=json.dumps(config).encode(),
)
config_address = result.address
print(f"Config scratchpad: {config_address}")
print(f"Cost: {result.cost} atto tokens")

# --- Reading config ---
def read_config(address: str) -> tuple[dict, int]:
    """Returns (config_dict, version_counter)."""
    pad = client.scratchpad_get(address)
    config = json.loads(pad.data)
    return config, pad.counter

cfg, version = read_config(config_address)
print(f"Config v{version}: {cfg}")

# --- Updating config ---
config["features"]["dark_mode"] = False
config["version"] = "1.1.0"

client.scratchpad_update(
    secret_key,
    content_type=CONFIG_TYPE,
    data=json.dumps(config).encode(),
)
print("Config updated")

cfg, version = read_config(config_address)
print(f"Config v{version}: {cfg}")

# --- Check if config changed ---
def has_changed(address: str, known_version: int) -> bool:
    """Quick check if config was updated since last read."""
    pad = client.scratchpad_get(address)
    return pad.counter > known_version

changed = has_changed(config_address, 0)
print(f"Changed since v0: {changed}")  # True
```

### C#

```csharp
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Antd.Sdk;

using var client = AntdClient.CreateRest();
var secretKey = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLower();

var config = new Dictionary<string, object>
{
    ["app_name"] = "MyApp",
    ["dark_mode"] = true,
    ["version"] = "1.0.0"
};

var result = await client.ScratchpadCreateAsync(
    secretKey,
    contentType: 1,
    data: Encoding.UTF8.GetBytes(JsonSerializer.Serialize(config))
);
Console.WriteLine($"Scratchpad: {result.Address}");

// Read
var pad = await client.ScratchpadGetAsync(result.Address);
Console.WriteLine($"Version {pad.Counter}: {Encoding.UTF8.GetString(pad.Data)}");

// Update
config["dark_mode"] = false;
config["version"] = "1.1.0";
await client.ScratchpadUpdateAsync(
    secretKey,
    contentType: 1,
    data: Encoding.UTF8.GetBytes(JsonSerializer.Serialize(config))
);

pad = await client.ScratchpadGetAsync(result.Address);
Console.WriteLine($"Version {pad.Counter}: {Encoding.UTF8.GetString(pad.Data)}");
```

### Kotlin

```kotlin
import com.autonomi.sdk.AntdClient
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class FeatureFlags(
    val darkMode: Boolean = true,
    val notifications: Boolean = true,
)

@Serializable
data class AppConfig(
    val appName: String,
    val features: FeatureFlags,
    val version: String,
)

const val CONFIG_TYPE = 1L

fun main() = runBlocking {
    val client = AntdClient.createRest()
    val secretKey = java.security.SecureRandom().nextBytes(ByteArray(32))
        .joinToString("") { "%02x".format(it) }

    // Initial config
    var config = AppConfig(
        appName = "MyApp",
        features = FeatureFlags(darkMode = true, notifications = true),
        version = "1.0.0",
    )

    // Create scratchpad with initial config
    val result = client.scratchpadCreate(
        secretKey,
        contentType = CONFIG_TYPE,
        data = Json.encodeToString(config).toByteArray(),
    )
    val configAddress = result.address
    println("Config scratchpad: $configAddress")
    println("Cost: ${result.cost} atto tokens")

    // --- Reading config ---
    suspend fun readConfig(address: String): Pair<AppConfig, Long> {
        val pad = client.scratchpadGet(address)
        val cfg = Json.decodeFromString<AppConfig>(String(pad.data))
        return cfg to pad.counter
    }

    val (cfg, version) = readConfig(configAddress)
    println("Config v$version: $cfg")

    // --- Updating config ---
    config = config.copy(
        features = config.features.copy(darkMode = false),
        version = "1.1.0",
    )

    client.scratchpadUpdate(
        secretKey,
        contentType = CONFIG_TYPE,
        data = Json.encodeToString(config).toByteArray(),
    )
    println("Config updated")

    val (updatedCfg, updatedVersion) = readConfig(configAddress)
    println("Config v$updatedVersion: $updatedCfg")

    // --- Check if config changed ---
    suspend fun hasChanged(address: String, knownVersion: Long): Boolean {
        val pad = client.scratchpadGet(address)
        return pad.counter > knownVersion
    }

    val changed = hasChanged(configAddress, 0)
    println("Changed since v0: $changed") // true
}
```

### Swift

```swift
import AntdSdk
import Foundation

let client = try AntdClient.createRest()

var bytes = [UInt8](repeating: 0, count: 32)
_ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
let secretKey = bytes.map { String(format: "%02x", $0) }.joined()

let configType: UInt64 = 1

// Initial config
var config: [String: Any] = [
    "app_name": "MyApp",
    "dark_mode": true,
    "version": "1.0.0",
]

// Create scratchpad with initial config
let jsonData = try JSONSerialization.data(withJSONObject: config)
let result = try await client.scratchpadCreate(
    ownerSecretKey: secretKey,
    contentType: configType,
    data: jsonData
)
let configAddress = result.address
print("Config scratchpad: \(configAddress)")
print("Cost: \(result.cost) atto tokens")

// --- Reading config ---
func readConfig(_ address: String) async throws -> ([String: Any], Int) {
    let pad = try await client.scratchpadGet(address: address)
    let cfg = try JSONSerialization.jsonObject(with: pad.data) as! [String: Any]
    return (cfg, pad.counter)
}

let (cfg, version) = try await readConfig(configAddress)
print("Config v\(version): \(cfg)")

// --- Updating config ---
config["dark_mode"] = false
config["version"] = "1.1.0"

let updatedJson = try JSONSerialization.data(withJSONObject: config)
try await client.scratchpadUpdate(
    ownerSecretKey: secretKey,
    contentType: configType,
    data: updatedJson
)
print("Config updated")

let (updatedCfg, updatedVersion) = try await readConfig(configAddress)
print("Config v\(updatedVersion): \(updatedCfg)")

// --- Check if config changed ---
func hasChanged(_ address: String, knownVersion: Int) async throws -> Bool {
    let pad = try await client.scratchpadGet(address: address)
    return pad.counter > knownVersion
}

let changed = try await hasChanged(configAddress, knownVersion: 0)
print("Changed since v0: \(changed)") // true
```

**Tradeoffs**:
- Single network operation to read (no pointer indirection).
- Built-in version counter for change detection.
- Previous versions are overwritten (no history).
- Data is encrypted on the network.

## Choosing Between Pointers and Scratchpads

| Aspect | Pointers | Scratchpads |
|--------|----------|-------------|
| Read latency | 2 operations (pointer + data) | 1 operation |
| Version history | Yes (old data persists) | No (overwritten) |
| Version counter | Yes (counter field) | Yes (counter field) |
| Data size | Unlimited (stored as Data) | Limited by scratchpad capacity |
| Data visibility | Public (if using public data) | Encrypted on network |
| Write cost | Data storage + pointer update | Scratchpad update |

**Use pointers when**: You want version history, large configs, or public readability.

**Use scratchpads when**: You want single-read performance, built-in encryption, or compact mutable state.

## Next Steps

- [Tutorial: Store & Retrieve Data](tutorial-store-retrieve.md) — Basics of immutable storage
- [Tutorial: Key-Value Store](tutorial-key-value-store.md) — Build a full KV store
- [Architecture Guide](architecture.md) — Understanding all data primitives
