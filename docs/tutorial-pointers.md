# Tutorial: Point at a Public File and Update It

Data on Autonomi is immutable: a new version of a file gets a new address. A **pointer** gives you one address that stays put while what it points at changes. It is a small, owner-signed, mutable reference: its address is derived from the owner's key and never changes, and the owner can point it at new data. Publish the pointer's address once, then move it to each new version.

This tutorial uploads a public file, points a pointer at it, uploads a second version, moves the pointer, and reads it back. Each step is shown in Python, C#, Kotlin, and Swift. The same calls over plain REST are at the end.

## Prerequisites

- The first antd release with pointers (after 0.15.0), on a local testnet with a wallet (`ant dev start` sets both up)
- An owner key loaded into antd (step 1)
- Python SDK installed (`pip install antd[rest]`), C# SDK built (`dotnet build`), Kotlin SDK built (`./gradlew build`), or Swift SDK built (`swift build`)

## 1. Create an Owner Key and Start antd With It

A pointer belongs to its owner key for life, because its address is derived from the key. antd holds the keys and signs with them, so requests name a pointer by its address and no key ever crosses the API.

Generate a key with the Autonomi `ant` CLI:

```bash
mkdir -p pointer-keys && chmod 700 pointer-keys
ant pointer keygen --output pointer-keys/notes.key
# Owner key written to pointer-keys/notes.key
# 6c399b78238ef9b15ffb66b3ea5bfe0fa573facaa3a438f93df371c020ba1f9d
```

The second line is the pointer's address: keep it, it is the `owner` in every call below. `ant pointer address --key pointer-keys/notes.key` prints it again. The key file holds the 32-byte ML-DSA-65 seed as hex on one line, and `keygen` refuses to overwrite an existing file.

> `ant pointer` is the Autonomi CLI from ant-client. The ant-sdk dev tool (`pip install -e ant-dev/`) also installs a command called `ant`, which only knows `ant dev ...`. If both are on your `PATH`, call the Autonomi CLI by its full path.

Then start antd with `--pointer-keys`, naming a key file or a directory of them (env `ANTD_POINTER_KEYS_DIR`). antd loads the keys once, at startup:

```bash
# With the dev CLI, which passes your environment on to antd
ANTD_POINTER_KEYS_DIR="$PWD/pointer-keys" ant dev start

# Or by hand, next to your usual flags
antd --pointer-keys ./pointer-keys
```

- In a directory, every regular file that is not hidden is a key. A file that is not a key, an empty directory or two copies of the same key stops antd at startup, so a missing key never shows up later as a write that cannot be signed.
- Without `--pointer-keys`, pointers can be read but not written.
- Keep the files readable only by the antd user; antd warns at startup on Unix when they are not. A pointer key is more sensitive than the wallet key: it cannot be rotated, and anyone holding it can hand the pointer over to themselves for good. See [SECURITY.md](../SECURITY.md).

Check that antd holds the key:

### Python

```python
from antd import AntdClient

client = AntdClient()

owner = "6c399b78238ef9b15ffb66b3ea5bfe0fa573facaa3a438f93df371c020ba1f9d"  # from keygen
assert owner in client.pointer_keys(), "antd holds no key for this pointer"
```

### C#

```csharp
using Antd.Sdk;

using var client = AntdClient.CreateRest();

var owner = "6c399b78238ef9b15ffb66b3ea5bfe0fa573facaa3a438f93df371c020ba1f9d"; // from keygen
if (!(await client.PointerKeysAsync()).Contains(owner))
    throw new InvalidOperationException("antd holds no key for this pointer");
```

### Kotlin

```kotlin
import com.autonomi.sdk.*
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    val client = AntdClient.createRest()

    val owner = "6c399b78238ef9b15ffb66b3ea5bfe0fa573facaa3a438f93df371c020ba1f9d" // from keygen
    check(owner in client.pointerKeys()) { "antd holds no key for this pointer" }
}
```

### Swift

```swift
import AntdSdk
import Foundation

let client = AntdClient.createRest()

let owner = "6c399b78238ef9b15ffb66b3ea5bfe0fa573facaa3a438f93df371c020ba1f9d" // from keygen
let keys = try await client.pointerKeys()
precondition(keys.contains { $0.address == owner }, "antd holds no key for this pointer")
```

The daemon accepts addresses with a `0x` prefix but always returns bare lowercase hex, so strip the prefix before comparing.

## 2. Upload the First Version

A public file's address is the address of its data map, a chunk, which is exactly what a pointer can point at. The daemon reads the file itself, so pass an absolute path.

### Python

```python
import os

path = os.path.abspath("notes.txt")
with open(path, "w") as f:
    f.write("Release notes, version 1\n")

v1 = client.file_put_public(path)
print(f"Version 1 at {v1.address}")
```

### C#

```csharp
var path = Path.Combine(Path.GetTempPath(), "notes.txt");
await File.WriteAllTextAsync(path, "Release notes, version 1\n");

var v1 = await client.FilePutPublicAsync(path);
Console.WriteLine($"Version 1 at {v1.Address}");
```

### Kotlin

```kotlin
val notes = java.io.File.createTempFile("notes", ".txt")
notes.writeText("Release notes, version 1\n")

val v1 = client.filePutPublic(notes.absolutePath)
println("Version 1 at ${v1.address}")
```

### Swift

```swift
let path = NSTemporaryDirectory() + "notes.txt"
try "Release notes, version 1\n".write(toFile: path, atomically: true, encoding: .utf8)

let v1 = try await client.filePutPublic(path: path, paymentMode: .auto)
print("Version 1 at \(v1.address)")
```

## 3. Create the Pointer

Creating the pointer stores its first state, at counter 0. **This pays**, about the price of one chunk, from the daemon wallet.

### Python

```python
w = client.pointer_create(owner, v1.address)   # pays
print(f"Pointer {w.address} -> version 1 (counter {w.counter})")
```

### C#

```csharp
var w = await client.PointerCreateAsync(owner, v1.Address);   // pays
Console.WriteLine($"Pointer {w.Address} -> version 1 (counter {w.Counter})");
```

### Kotlin

```kotlin
val w = client.pointerCreate(owner, v1.address)   // pays
println("Pointer ${w.address} -> version 1 (counter ${w.counter})")
```

### Swift

```swift
let w = try await client.pointerCreate(owner: owner, target: v1.address, kind: .chunk)  // pays
print("Pointer \(w.address) -> version 1 (counter \(w.counter))")
```

The pointer's address is the `owner` address: the one `keygen` printed. Hand it out wherever you would have handed out `v1.address`.

A pointer is created once. Creating it again is refused before anything is paid (`409 ALREADY_EXISTS`); move an existing pointer with an update.

## 4. Upload Version 2 and Update the Pointer

Upload the new version, then point the pointer at it. The address stays the same and the counter goes up by one. **This pays again.**

### Python

```python
with open(path, "w") as f:
    f.write("Release notes, version 2\n")

v2 = client.file_put_public(path)
w = client.pointer_update(owner, v2.address)   # pays
print(f"Pointer -> version 2 (counter {w.counter})")   # counter 1
```

### C#

```csharp
await File.WriteAllTextAsync(path, "Release notes, version 2\n");

var v2 = await client.FilePutPublicAsync(path);
w = await client.PointerUpdateAsync(owner, v2.Address);   // pays
Console.WriteLine($"Pointer -> version 2 (counter {w.Counter})");
```

### Kotlin

```kotlin
notes.writeText("Release notes, version 2\n")

val v2 = client.filePutPublic(notes.absolutePath)
val updated = client.pointerUpdate(owner, v2.address)   // pays
println("Pointer -> version 2 (counter ${updated.counter})")
```

### Swift

```swift
try "Release notes, version 2\n".write(toFile: path, atomically: true, encoding: .utf8)

let v2 = try await client.filePutPublic(path: path, paymentMode: .auto)
let updated = try await client.pointerUpdate(owner: owner, target: v2.address, kind: .chunk)  // pays
print("Pointer -> version 2 (counter \(updated.counter))")
```

An update creates the pointer if it does not exist yet. It is refused before paying once the pointer is final (`409 POINTER_FINAL`, see [Transfer](#7-transfer-irreversible)).

## 5. Resolve the Pointer and Fetch the File

A reader needs only the pointer's address. `resolve` follows the pointer, and any chain of pointers behind it (at most 16 hops), to the target at the end. Reads are free.

### Python

```python
target = client.pointer_resolve(owner)
dest = path + ".latest"
client.file_get_public(target.target, dest)

with open(dest) as f:
    print(f.read())   # "Release notes, version 2"
```

### C#

```csharp
var target = await client.PointerResolveAsync(owner);
var dest = path + ".latest";
await client.FileGetPublicAsync(target.Target, dest);

Console.WriteLine(await File.ReadAllTextAsync(dest));   // "Release notes, version 2"
```

### Kotlin

```kotlin
val target = client.pointerResolve(owner)
val dest = notes.absolutePath + ".latest"
client.fileGetPublic(target.target, dest)

println(java.io.File(dest).readText())   // "Release notes, version 2"
```

### Swift

```swift
let target = try await client.pointerResolve(address: owner)
let dest = path + ".latest"
try await client.fileGetPublic(address: target.target, destPath: dest)

print(try String(contentsOfFile: dest, encoding: .utf8))   // "Release notes, version 2"
```

`get` reads the pointer's own record instead: its `counter`, `target`, `kind`, whether it is final (`is_final` / `IsFinal` / `isFinal`), `transferred_to`, and the owner's ML-DSA-65 public key.

## 6. Check Finality

`finality` asks every peer of the pointer's close group where the pointer stands. It is free, and it is how you check a transfer landed before relying on it.

### Python

```python
f = client.pointer_finality(owner)
print(f"{f.status.value}: {f.answered}/{f.group} peers answered, counter {f.counter}")
# open: 7/7 peers answered, counter 1
```

### C#

```csharp
var f = await client.PointerFinalityAsync(owner);
Console.WriteLine($"{f.RawStatus}: {f.Answered}/{f.Group} peers answered, counter {f.Counter}");
```

### Kotlin

```kotlin
val f = client.pointerFinality(owner)
println("${f.status.wire}: ${f.answered}/${f.group} peers answered, counter ${f.counter}")
```

### Swift

```swift
let f = try await client.pointerFinality(address: owner)
print("\(f.status.wire): \(f.answered)/\(f.group) peers answered, counter \(f.counter.map(String.init) ?? "none")")
```

The status is one of:

- **open**: no peer that answered holds a final state, so the owner can still move the pointer; `counter` is the current state's.
- **settling**: one final state and no rival, but a majority of the group does not hold it yet (a transfer still spreading).
- **unconfirmed**: one final state, held by a majority, but not every peer answered, so a rival could be hiding; ask again.
- **final**: one final state, held by a majority, every peer answered and none holds a rival. Only this means a transfer is beyond dispute.
- **forked**: the owner signed two or more different final states; `majority` is the one reads return, if any.

Each SDK also has an "unknown" case for a status a newer daemon may add, with the daemon's string kept (`raw_status` / `RawStatus` / `Unknown(wire)` / `.unknown(String)`).

## 7. Transfer (Irreversible)

A transfer hands the pointer over, for good, to another pointer: the recipient's, which must already exist. It stores the pointer's final state. Readers of the address are redirected to the recipient's pointer, the address stays the same, and the old key can change nothing ever again. **It pays, and it cannot be undone**: no call reverses it, not even by the old owner.

```python
result = client.pointer_transfer(owner, recipient)   # pays; irreversible
if result.finality is not None:
    print(result.finality.status.value)   # wait for "final" before relying on it
else:
    print(f"stored, but the finality check failed: {result.finality_error}")
```

The other SDKs call it `PointerTransferAsync` (C#), `pointerTransfer` (Kotlin), and `pointerTransfer(owner:recipient:)` (Swift). antd refuses a transfer, before paying, if the pointer is already final, if the recipient does not exist or leads back to this pointer, or if not every peer of the close group answered (`503 CLOSE_GROUP_SHORTFALL`, free to retry). After the transfer, check `pointer_finality` until it reports `final`, and `pointer_controller` to follow transfers to the pointer whose owner now decides.

Use a fresh key for each pointer you receive by transfer.

## 8. What It Costs

- Every **create, update and transfer pays**, about the price of one chunk, from the daemon wallet. Reads (`keys`, `get`, `resolve`, `finality`, `controller`) are free.
- **Every attempt pays again**, so the SDKs never retry a paid pointer write on their own, and you should not wrap one in an automatic retry either. If a write fails partway, read the pointer with `get` to see what landed before you pay for another attempt.
- antd serialises writes to one pointer: two writes signed against the same counter would both pay, and only one could survive.

## 9. Paying With an External Signer

An application that keeps its own wallet can sign the payment itself. antd still signs the pointer state with the owner key it holds; `prepare` signs and quotes the write without paying, and `finalize` stores it once your signer has paid. It needs no daemon wallet.

```python
from antd import PointerOp

prep = client.pointer_prepare(owner, PointerOp.UPDATE, target=v2.address)
# prep.payments, prep.total_amount, prep.payment_vault_address, prep.rpc_url:
# your signer approves the token and calls payForQuotes(prep.payments)
done = client.pointer_finalize(prep.upload_id, {"0xquotehash": "0xtxhash"})
print(f"counter {done.counter}")
```

A pointer write is always paid as a wave batch (`payment_type` `"wave_batch"`), never a merkle payment. While a prepared write awaits payment (up to an hour), other writes to that pointer are refused with `409 CONFLICT`. A finalize that falls short after payment raises `CloseGroupShortfallError` with `retryable` set: the daemon kept the paid state, so call `pointer_finalize` again with the same `upload_id` to store it against the same payment, and bound that loop. The payment side (ABI, approvals, the `payForQuotes()` call) is the same as for uploads: see [External Signer Flow](external-signer-flow.md).

## 10. Why Counters Are Strings

Each state of a pointer carries a counter, an unsigned 64-bit number that rises with every update. A final state, the one a transfer stores, sits at the top of the range, 2^64 − 1 = `18446744073709551615`. JSON numbers lose precision above 2^53 in many languages, so antd sends counters as decimal strings over REST and gRPC alike. Each SDK parses them into an exact unsigned 64-bit type (`int` in Python, `ulong` in C#, `ULong` in Kotlin, `UInt64` in Swift) or keeps the checked string, and rejects a malformed counter instead of reading it as 0. Compare counters as numbers, not as strings.

## Error Handling

The pointer errors come with their own codes, so they never read as `AlreadyExists`:

| Code | HTTP | When |
|------|------|------|
| `ALREADY_EXISTS` | 409 | A create of a pointer that exists. Nothing paid |
| `POINTER_FINAL` | 409 | A write to a pointer that was transferred or is otherwise final. Nothing paid |
| `POINTER_FORKED` | 409 | The owner signed two final states and no majority holds either |
| `CONFLICT` | 409 | A prepared write to the pointer awaits payment, or an update lost to a newer state |
| `CLOSE_GROUP_SHORTFALL` | 503 | Too few of the close group answered or stored. Reads are free to retry; `retryable` is true only for a finalize that kept the paid state |

Over gRPC these share status codes with older errors, so antd names them in an `x-antd-error-code` trailer, which the SDKs read.

### Python

```python
from antd import CloseGroupShortfallError, ConflictError, PointerFinalError

try:
    client.pointer_update(owner, v2.address)
except PointerFinalError:
    print("Transferred or final: nothing can move it, and nothing was paid")
except ConflictError:
    print("A prepared write awaits payment: finalize it or wait for it to expire")
except CloseGroupShortfallError:
    print("May or may not have landed: read it with pointer_get before paying again")
```

### C#

```csharp
try
{
    await client.PointerUpdateAsync(owner, v2.Address);
}
catch (PointerFinalException)
{
    Console.WriteLine("Transferred or final: nothing can move it, and nothing was paid");
}
catch (ConflictException)
{
    Console.WriteLine("A prepared write awaits payment: finalize it or wait for it to expire");
}
catch (CloseGroupShortfallException)
{
    Console.WriteLine("May or may not have landed: read it with PointerGetAsync before paying again");
}
```

### Kotlin

```kotlin
try {
    client.pointerUpdate(owner, v2.address)
} catch (e: PointerFinalException) {
    println("Transferred or final: nothing can move it, and nothing was paid")
} catch (e: ConflictException) {
    println("A prepared write awaits payment: finalize it or wait for it to expire")
} catch (e: CloseGroupShortfallException) {
    println("May or may not have landed: read it with pointerGet before paying again")
}
```

### Swift

```swift
do {
    _ = try await client.pointerUpdate(owner: owner, target: v2.address, kind: .chunk)
} catch is PointerFinalError {
    print("Transferred or final: nothing can move it, and nothing was paid")
} catch is ConflictError {
    print("A prepared write awaits payment: finalize it or wait for it to expire")
} catch is CloseGroupShortfallError {
    print("May or may not have landed: read it with pointerGet before paying again")
}
```

## Over Plain REST

The same walk-through with `curl` and `jq`, against antd on its default port. Every SDK makes these calls under the hood.

```bash
ANTD=http://localhost:8082
OWNER=6c399b78238ef9b15ffb66b3ea5bfe0fa573facaa3a438f93df371c020ba1f9d   # from keygen

# Is the key loaded?
curl -s $ANTD/v1/pointers/keys
# {"keys":[{"address":"6c399b78..."}]}

# Upload version 1 (the daemon reads the path, so make it absolute)
echo "Release notes, version 1" > notes.txt
V1=$(curl -s -X POST $ANTD/v1/files/public \
  -H 'Content-Type: application/json' \
  -d "{\"path\": \"$PWD/notes.txt\"}" | jq -r .address)

# Create the pointer (pays)
curl -s -X POST $ANTD/v1/pointers \
  -H 'Content-Type: application/json' \
  -d "{\"owner\": \"$OWNER\", \"target\": \"$V1\"}"
# {"address":"6c399b78...","state_id":"5cf979cb...","counter":"0"}

# Upload version 2 and move the pointer (pays)
echo "Release notes, version 2" > notes.txt
V2=$(curl -s -X POST $ANTD/v1/files/public \
  -H 'Content-Type: application/json' \
  -d "{\"path\": \"$PWD/notes.txt\"}" | jq -r .address)
curl -s -X POST $ANTD/v1/pointers/update \
  -H 'Content-Type: application/json' \
  -d "{\"owner\": \"$OWNER\", \"target\": \"$V2\"}"
# {"address":"6c399b78...","state_id":"4a76345c...","counter":"1"}

# Resolve it and fetch the file it leads to (free)
TARGET=$(curl -s $ANTD/v1/pointers/$OWNER/resolve | jq -r .target)
curl -s -X POST $ANTD/v1/files/public/get \
  -H 'Content-Type: application/json' \
  -d "{\"address\": \"$TARGET\", \"dest_path\": \"$PWD/notes-latest.txt\"}"
cat notes-latest.txt
# Release notes, version 2

# Read the record and its finality (free)
curl -s $ANTD/v1/pointers/$OWNER | jq -c '{counter, kind, target, is_final, transferred_to}'
# {"counter":"1","kind":"chunk","target":"41bed792...","is_final":false,"transferred_to":null}
curl -s $ANTD/v1/pointers/$OWNER/finality
# {"address":"6c399b78...","group":7,"answered":7,"status":"open","counter":"1","state":null,"states":[],"majority":null,"transferred_to":null}
```

A second `POST /v1/pointers` for the same owner answers `409` with `"code":"ALREADY_EXISTS"` and pays nothing. A transfer is `POST /v1/pointers/transfer` with `{"owner": "...", "recipient": "..."}`; the external-signer pair is `POST /v1/pointers/prepare` and `POST /v1/pointers/finalize`. The full route list is in the Pointers section of [llms-full.txt](../llms-full.txt).

## Next Steps

- [Tutorial: Store and Retrieve Data](tutorial-store-retrieve.md): the immutable data a pointer points at
- [External Signer Flow](external-signer-flow.md): paying from your own wallet
- [Architecture Guide](architecture.md): the full data model
- Each SDK has a runnable pointers example: `ANTD_POINTER_OWNER=<address> ant dev example pointers -l <language>` (see the [README](../README.md#pointers) for the file in each SDK)
