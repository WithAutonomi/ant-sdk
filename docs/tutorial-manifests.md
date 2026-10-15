# Tutorial: Share a Set of Files as One Link

Data on Autonomi is addressed one file at a time: upload three files and you have three addresses to hand out. A **manifest** describes the set as a single document, and when it is small enough, as a single `ant://manifest/` link. Each entry lists a file's path and either the file's public address or its DataMap, the key to a private file. Send the link and the receiver learns what is in the set, what each file is called and how to fetch each one.

This tutorial uploads three files, builds a manifest with paths and a name, shares the link, and has the receiver decode it and download every entry. Each step is shown in Python, C#, Kotlin, and Swift. The same calls over plain REST are at the end.

Building and decoding a manifest **upload nothing and pay nothing**. Only the file uploads in step 1 cost anything.

## Prerequisites

- The antd release after 0.15.0, the first with manifests, on a local testnet with a wallet (`ant dev start` sets both up). The wallet is needed for the uploads only; the manifest calls need none
- Python SDK installed (`pip install antd[rest]`), C# SDK built (`dotnet build`), Kotlin SDK built (`./gradlew build`), or Swift SDK built (`swift build`)
- Three small files. Make them:

```bash
mkdir -p trip && cd trip
echo "Day one: we arrived in Lisbon." > intro.txt
echo "Map notes: the tram runs along the river." > map.txt
echo "Private diary: bring more coffee." > diary.txt
```

## 1. Upload the Files

A manifest is built from files that are already on the network, so upload first. The daemon reads each file itself, so pass absolute paths.

- `intro.txt` and `map.txt` go up as **public** files. Each upload returns the file's address, and anyone who knows the address can read the file.
- `diary.txt` goes up as a **private** file. The upload returns its DataMap, which is the only key to the file. Keep it as secret as the file itself.

Each upload pays.

### Python

```python
import os
from antd import AntdClient

client = AntdClient()

intro = client.file_put_public(os.path.abspath("intro.txt"))   # pays
notes = client.file_put_public(os.path.abspath("map.txt"))     # pays
diary = client.file_put(os.path.abspath("diary.txt"))          # pays; private

print(intro.address, notes.address)
print(diary.data_map[:32], "...")   # the key to the private file
```

### C#

```csharp
using Antd.Sdk;

using var client = AntdClient.CreateRest();

var intro = await client.FilePutPublicAsync(Path.GetFullPath("intro.txt"));   // pays
var notes = await client.FilePutPublicAsync(Path.GetFullPath("map.txt"));     // pays
var diary = await client.FilePutAsync(Path.GetFullPath("diary.txt"));         // pays; private

Console.WriteLine($"{intro.Address} {notes.Address}");
Console.WriteLine(diary.DataMap[..32] + "...");   // the key to the private file
```

### Kotlin

```kotlin
import com.autonomi.sdk.*
import java.io.File
import kotlinx.coroutines.runBlocking

fun main() = runBlocking {
    val client = AntdClient.createRest()

    val intro = client.filePutPublic(File("intro.txt").absolutePath)   // pays
    val notes = client.filePutPublic(File("map.txt").absolutePath)     // pays
    val diary = client.filePut(File("diary.txt").absolutePath)         // pays; private

    println("${intro.address} ${notes.address}")
    println(diary.dataMap.take(32) + "...")   // the key to the private file
}
```

### Swift

```swift
import AntdSdk
import Foundation

let client = AntdClient.createRest()
func here(_ name: String) -> String { FileManager.default.currentDirectoryPath + "/" + name }

let intro = try await client.filePutPublic(path: here("intro.txt"), paymentMode: .auto)   // pays
let notes = try await client.filePutPublic(path: here("map.txt"), paymentMode: .auto)     // pays
let diary = try await client.filePut(path: here("diary.txt"), paymentMode: .auto)         // pays; private

print(intro.address, notes.address)
print(diary.dataMap.prefix(32), "...")   // the key to the private file
```

## 2. Build the Manifest

Describe each file as one entry: a `path` (where the receiver should put it), and **exactly one** of `address` (a public file) or `data_map` (a private file, embedded). Both or neither is refused before anything is sent, with the same bad-request error (status 400) the daemon would give. Add a `name` for the set as a whole, a suggested root directory. Paths are relative and portable: no `..`, no leading slash.

`size` is optional. If you give one it is recorded as you gave it, the creator's claim. Unset means none is recorded, never `0`.

### Python

```python
from antd import ManifestEntryInput

built = client.build_manifest(                                     # free
    [
        ManifestEntryInput(path="intro.txt", address=intro.address, size=31),
        ManifestEntryInput(path="maps/map.txt", address=notes.address),
        ManifestEntryInput(path="private/diary.txt", data_map=diary.data_map),
    ],
    name="lisbon-trip",
)

print(built.link)                          # ant://manifest/...
print(len(built.manifest), "bytes of .ant")
for e in built.entries:
    print(e.effective_name, e.kind, e.content_address[:8])
```

### C#

```csharp
var built = await client.BuildManifestAsync(new[]                  // free
{
    ManifestEntryInput.Public(intro.Address, "intro.txt", size: 31),
    ManifestEntryInput.Public(notes.Address, "maps/map.txt"),
    ManifestEntryInput.Embedded(diary.DataMap, "private/diary.txt"),
}, new BuildManifestOptions(Name: "lisbon-trip"));

Console.WriteLine(built.Link);                            // ant://manifest/...
Console.WriteLine($"{built.Manifest.Length} bytes of .ant");
foreach (var e in built.Entries)
    Console.WriteLine($"{e.EffectiveName} {e.Kind} {e.ContentAddress[..8]}");
```

### Kotlin

```kotlin
val built = client.buildManifest(                                  // free
    listOf(
        ManifestEntryInput(path = "intro.txt", address = intro.address, size = 31UL),
        ManifestEntryInput(path = "maps/map.txt", address = notes.address),
        ManifestEntryInput(path = "private/diary.txt", dataMap = diary.dataMap),
    ),
    BuildManifestOptions(name = "lisbon-trip"),
)

println(built.link)                                       // ant://manifest/...
println("${built.manifest.size} bytes of .ant")
built.entries.forEach { println("${it.effectiveName} ${it.kind} ${it.contentAddress.take(8)}") }
```

### Swift

```swift
let built = try await client.buildManifest(                        // free
    entries: [
        ManifestEntryInput(path: "intro.txt", size: 31, address: intro.address),
        ManifestEntryInput(path: "maps/map.txt", address: notes.address),
        ManifestEntryInput(path: "private/diary.txt", dataMap: diary.dataMap),
    ],
    options: BuildManifestOptions(name: "lisbon-trip")
)

print(built.link ?? "too big for a link")                  // ant://manifest/...
print(built.manifest.count, "bytes of .ant")
for e in built.entries { print(e.effectiveName, e.kind, e.contentAddress.prefix(8)) }
```

The result holds three things:

- `manifest`: the raw `.ant` bytes. In every SDK these are plain bytes; the base64 REST carries them in never reaches you.
- `link`: the `ant://manifest/...` link, only when it fits the 1,500-byte limit (step 6). Otherwise it is empty or none.
- `entries`: what the manifest says about each file, **sorted by effective name** (the path, or the content address when there is no path), not in the order you gave them.

The two public entries show no `exact_size` yet: a public entry only names an address. The private entry already has one, because an embedded DataMap carries the file's size.

## 3. Share the Link

The link is the whole manifest. Put it in a message, a QR code or a web page; there is nothing to publish and no server to keep running. If you would rather ship a file, write `built.manifest` to disk as `trip.ant` and send that instead; it decodes the same way.

Anyone holding the link or the file can learn every path in the set and can read **every embedded entry**, because the DataMap is the key to the private file. Share it as widely as you are happy for the private files to travel. Public entries are readable by anyone who knows the address, with or without the manifest.

## 4. The Receiver Decodes It

The receiver needs only the link and an antd daemon. Decoding with `resolve` also asks the network for each entry's DataMap, to confirm it is there and report the file's `exact_size`. It does not download the files.

### Python

```python
decoded = client.decode_manifest_link(link, resolve=True)   # free

print(decoded.source, decoded.name)        # manifest lisbon-trip
for e in decoded.entries:
    print(e.effective_name, e.kind, e.size, e.exact_size, e.error)
```

### C#

```csharp
var decoded = await client.DecodeManifestLinkAsync(link, resolve: true);   // free

Console.WriteLine($"{decoded.Source} {decoded.Name}");
foreach (var e in decoded.Entries)
    Console.WriteLine($"{e.EffectiveName} {e.Kind} {e.Size} {e.ExactSize} {e.Error}");
```

### Kotlin

```kotlin
val decoded = client.decodeManifestLink(link, resolve = true)   // free

println("${decoded.source} ${decoded.name}")
decoded.entries.forEach { println("${it.effectiveName} ${it.kind} ${it.size} ${it.exactSize} ${it.error}") }
```

### Swift

```swift
let decoded = try await client.decodeManifestLink(link, resolve: true)   // free

print(decoded.source, decoded.name ?? "")
for e in decoded.entries {
    print(e.effectiveName, e.kind, e.size ?? 0, e.exactSize ?? 0, e.error ?? "")
}
```

What comes back for the trip:

| effective_name | kind | size | exact_size | data_map |
|----------------|------|------|------------|----------|
| `intro.txt` | `public` | 31 (you gave it) | 31 | none |
| `maps/map.txt` | `public` | none | 42 | none |
| `private/diary.txt` | `embedded` | none | 34 | the DataMap, hex |

- `size` is only what the creator recorded. `exact_size` is read from the network, so trust that one.
- Without `resolve`, only entries with an embedded DataMap have an `exact_size`; the rest stay unset until you ask.
- If one entry cannot be resolved, say its DataMap is not on the network, its `error` says why and the call still succeeds. Check `error` per entry.
- `decode_manifest_link` also accepts a file link or a bare address. Those come back with `source` `file_link` and one public entry with no path.
- A receiver holding `.ant` bytes calls `decode_manifest(bytes, resolve)` instead.

## 5. Download Each Entry

A manifest does not download anything. It tells the receiver which existing download call to make for each entry, by `kind`:

- **`public`**: download **by address**, with `content_address`. This is the same call as for any public file.
- **`embedded`**: download **by DataMap**, with `data_map`. This is the same call as for any private file.

The daemon writes each file where you tell it, and the folder must already exist, so create the folders from the paths first.

### Python

```python
out = os.path.abspath("received")

for e in decoded.entries:
    dest = os.path.join(out, e.effective_name)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if e.kind == "public":
        client.file_get_public(e.content_address, dest)
    else:
        client.file_get(e.data_map, dest)
```

### C#

```csharp
var outDir = Path.GetFullPath("received");

foreach (var e in decoded.Entries)
{
    var dest = Path.Combine(outDir, e.EffectiveName);
    Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
    if (e.Kind == "public")
        await client.FileGetPublicAsync(e.ContentAddress, dest);
    else
        await client.FileGetAsync(e.DataMap!, dest);
}
```

### Kotlin

```kotlin
val outDir = File("received").absoluteFile

decoded.entries.forEach { e ->
    val dest = File(outDir, e.effectiveName)
    dest.parentFile.mkdirs()
    if (e.kind == "public") {
        client.fileGetPublic(e.contentAddress, dest.path)
    } else {
        client.fileGet(e.dataMap!!, dest.path)
    }
}
```

### Swift

```swift
let outDir = FileManager.default.currentDirectoryPath + "/received"

for e in decoded.entries {
    let dest = outDir + "/" + e.effectiveName
    try FileManager.default.createDirectory(
        atPath: (dest as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true)
    if e.kind == "public" {
        try await client.fileGetPublic(address: e.contentAddress, destPath: dest)
    } else {
        try await client.fileGet(dataMap: e.dataMap!, destPath: dest)
    }
}
```

After this, `received/` holds `intro.txt`, `maps/map.txt` and `private/diary.txt`, identical to what was uploaded. To read an entry into memory instead of a file, use the data calls the same way: `data_get_public(address)` for a public entry and `data_get(data_map)` for an embedded one (`GET /v1/data/public/{addr}`, and `POST /v1/data/get` with the DataMap).

The receiver needs no wallet for any of this: downloads are free.

## 6. Embedded DataMaps or Public Addresses

Both kinds can sit in the same manifest. Choose per file.

| | Public address | Embedded DataMap |
|---|---|---|
| Upload with | `file_put_public` / `data_put_public` | `file_put` / `data_put` |
| Who can read the file | Anyone who knows the address | Anyone who holds the manifest or link |
| Cost in the link | Small: about 60 bytes plus the path | Large: a DataMap, 300 bytes for a tiny file, more for a big one |
| Receiver downloads by | `content_address` | `data_map` |
| The upload also stores | the file's DataMap, so it can be fetched by address | nothing: the DataMap lives only in the manifest |

Use **public addresses** when the files are meant for anyone, or when you want the link to stay short. Use **embedded DataMaps** when the manifest itself is the access control: whoever you hand the link or `.ant` file to can read the files, and nobody else can, because the DataMap exists nowhere else on the network.

Large private files help themselves: by default (`embed_roots` on, `KeepShrunkDataMaps` off in Go, Java, C++ and Rust) the daemon resolves a large file's shrunk DataMap and embeds its small root instead when that root is at most 64 KiB, as the `ant` CLI does. The receiver then skips that fetch and `exact_size` is known. Set `embed_roots` to false (`keep_shrunk_data_maps` / `KeepShrunkDataMaps` true in those four SDKs) to embed DataMaps exactly as you passed them.

`content_address` is a file's public DataMap address whether or not the file was ever made public. A private upload has one too, but nothing is stored there, so only the DataMap fetches a private file.

## 7. The 1,500-Byte Link Limit

A link is recommended to stay within **1,500 bytes** of manifest, about 2,000 characters once encoded. When the manifest is bigger, the daemon still builds it: `manifest` holds the full `.ant` bytes, and `link` is simply left out (empty, none or null, depending on the SDK). Nothing fails.

Roughly, 16 to 20 public entries with short paths fit in a link, and only a handful of embedded ones. Past the limit:

- **Share the `.ant` bytes instead.** Write `built.manifest` to a file, host it, attach it, or send it any way you like. The receiver decodes it with `decode_manifest(bytes, resolve)`; it is the same call as for a link, with the same result.
- **Split the set** into several smaller manifests, each with its own link.
- **Prefer public addresses**, which cost far fewer bytes than embedded DataMaps.

A manifest is bounded at 64 MiB and 100,000 entries. Code that expects a link should check for an empty one:

### Python

```python
if built.link:
    share(built.link)
else:
    with open("trip.ant", "wb") as f:
        f.write(built.manifest)       # raw .ant bytes: share this file instead

# receiver, from the file
decoded = client.decode_manifest(open("trip.ant", "rb").read(), resolve=True)
```

### C#

```csharp
if (built.Link is { } link)
    Share(link);
else
    await File.WriteAllBytesAsync("trip.ant", built.Manifest);   // raw .ant bytes

// receiver, from the file
var decoded = await client.DecodeManifestAsync(await File.ReadAllBytesAsync("trip.ant"), resolve: true);
```

### Kotlin

```kotlin
val link = built.link
if (link != null) share(link) else File("trip.ant").writeBytes(built.manifest)   // raw .ant bytes

// receiver, from the file
val decoded = client.decodeManifest(File("trip.ant").readBytes(), resolve = true)
```

### Swift

```swift
if let link = built.link {
    share(link)
} else {
    try built.manifest.write(to: URL(fileURLWithPath: "trip.ant"))   // raw .ant bytes
}

// receiver, from the file
let decoded = try await client.decodeManifest(Data(contentsOf: URL(fileURLWithPath: "trip.ant")), resolve: true)
```

## 8. What It Costs

- **Building and decoding pay nothing**, and they upload nothing. A manifest lives in the link or the file you share, not on the network. The daemon needs no wallet for them.
- **Uploading the files pays**, as it always does: that is step 1. Uploading the same bytes again costs nothing extra, because the content already exists.
- **Reads are free**, so the receiver pays nothing to decode or to download.
- Build (with the default root embedding) and a decode with `resolve` do read from the network, to resolve DataMaps. A read can time out; since nothing is paid, retrying is safe.

## Error Handling

There are no manifest-specific error codes. An invalid entry or input is a `400 BAD_REQUEST` (gRPC `INVALID_ARGUMENT`), and the message counts and names every bad entry by index, for example `2 invalid entries: entries[0]: invalid path "../x": ...; entries[1]: needs a data_map or an address` (at most 20 are shown, then `; and K more`). Every SDK raises its usual bad-request error and keeps that message; over REST it carries a leading `Bad request: `, over gRPC it is bare. One entry that cannot be resolved during a decode is not an error: it is reported in that entry's `error`.

### Python

```python
from antd import BadRequestError, ManifestEntryInput

try:
    client.build_manifest([ManifestEntryInput(path="../x", address=intro.address)])
except BadRequestError as e:
    print(e)    # 1 invalid entries: entries[0]: invalid path "../x": ...
```

### C#

```csharp
try
{
    await client.BuildManifestAsync(new[] { ManifestEntryInput.Public(intro.Address, "../x") });
}
catch (BadRequestException e)
{
    Console.WriteLine(e.Message);    // 1 invalid entries: entries[0]: invalid path "../x": ...
}
```

### Kotlin

```kotlin
try {
    client.buildManifest(listOf(ManifestEntryInput(path = "../x", address = intro.address)))
} catch (e: BadRequestException) {
    println(e.message)    // 1 invalid entries: entries[0]: invalid path "../x": ...
}
```

### Swift

```swift
do {
    _ = try await client.buildManifest(entries: [ManifestEntryInput(path: "../x", address: intro.address)])
} catch let e as BadRequestError {
    print(e)    // 1 invalid entries: entries[0]: invalid path "../x": ...
}
```

An entry with both or neither of `address` and `data_map` is refused before the request is sent. Every SDK raises the same bad-request error, with status 400 and the daemon's message text, so a refusal on the client is indistinguishable from the daemon's own 400, and nothing reaches the daemon. An empty decode input (neither bytes nor a link) is refused the same way: `needs a manifest (base64 .ant bytes) or a link`.

## Over Plain REST

The same walk-through with `curl` and `jq`, against antd on its default port. Every SDK makes these calls under the hood. On REST the `.ant` bytes travel as base64 in the `manifest` field; the SDKs hide that.

```bash
ANTD=http://localhost:8082
cd trip

# Upload (pays): two public files, one private
INTRO=$(curl -s -X POST $ANTD/v1/files/public \
  -H 'Content-Type: application/json' \
  -d "{\"path\": \"$PWD/intro.txt\"}" | jq -r .address)
MAP=$(curl -s -X POST $ANTD/v1/files/public \
  -H 'Content-Type: application/json' \
  -d "{\"path\": \"$PWD/map.txt\"}" | jq -r .address)
DIARY=$(curl -s -X POST $ANTD/v1/files \
  -H 'Content-Type: application/json' \
  -d "{\"path\": \"$PWD/diary.txt\"}" | jq -r .data_map)

# Build the manifest (free)
curl -s -X POST $ANTD/v1/manifests/build \
  -H 'Content-Type: application/json' \
  -d "{
    \"name\": \"lisbon-trip\",
    \"entries\": [
      {\"path\": \"intro.txt\", \"address\": \"$INTRO\", \"size\": 31},
      {\"path\": \"maps/map.txt\", \"address\": \"$MAP\"},
      {\"path\": \"private/diary.txt\", \"data_map\": \"$DIARY\"}
    ]}" > built.json
jq -c '.entries[] | {effective_name, kind, content_address: .content_address[0:8], exact_size}' built.json
# {"effective_name":"intro.txt","kind":"public","content_address":"972d63ab","exact_size":null}
# {"effective_name":"maps/map.txt","kind":"public","content_address":"16b60f56","exact_size":null}
# {"effective_name":"private/diary.txt","kind":"embedded","content_address":"598c13df","exact_size":34}
LINK=$(jq -r .link built.json)       # null when the manifest is too big for a link
echo "$LINK"
# ant://manifest/wUFOVAGCpG5hbWWrbGlzYm9uLXRyaXCnZW5...

# The receiver decodes it, resolving exact sizes (free)
curl -s -X POST $ANTD/v1/manifests/decode \
  -H 'Content-Type: application/json' \
  -d "{\"link\": \"$LINK\", \"resolve\": true}" > decoded.json
jq -c '{source, name, entries: [.entries[] | {effective_name, kind, size, exact_size, error}]}' decoded.json
# {"source":"manifest","name":"lisbon-trip","entries":[{"effective_name":"intro.txt","kind":"public","size":31,"exact_size":31,"error":null},...]}

# Download every entry: public by address, embedded by DataMap
mkdir -p received/maps received/private
jq -c '.entries[]' decoded.json | while read -r E; do
  NAME=$(jq -r .effective_name <<<"$E")
  if [ "$(jq -r .kind <<<"$E")" = public ]; then
    curl -s -X POST $ANTD/v1/files/public/get -H 'Content-Type: application/json' \
      -d "{\"address\": \"$(jq -r .content_address <<<"$E")\", \"dest_path\": \"$PWD/received/$NAME\"}"
  else
    curl -s -X POST $ANTD/v1/files/get -H 'Content-Type: application/json' \
      -d "{\"data_map\": \"$(jq -r .data_map <<<"$E")\", \"dest_path\": \"$PWD/received/$NAME\"}"
  fi
done
cat received/intro.txt received/maps/map.txt received/private/diary.txt
# Day one: we arrived in Lisbon.
# Map notes: the tram runs along the river.
# Private diary: bring more coffee.
```

To decode the raw bytes instead of a link, send `{"manifest": "<base64 .ant>", "resolve": true}`: `jq -r .manifest built.json` is exactly that base64. Give `manifest` or `link`, not both.

A manifest too big for a link has no `link` field, and `manifest` is all you share:

```bash
# 40 public entries: 4,064 bytes of .ant, and no "link" in the response
jq -n --arg a "$INTRO" '{entries: [range(0;40) | {path: "file-\(.).txt", address: $a}]}' \
  | curl -s -X POST $ANTD/v1/manifests/build -H 'Content-Type: application/json' -d @- \
  | jq -c '{has_link: has("link"), entries: (.entries | length)}'
# {"has_link":false,"entries":40}
```

An invalid entry answers `400`, naming each one:

```bash
curl -s -X POST $ANTD/v1/manifests/build -H 'Content-Type: application/json' \
  -d "{\"entries\":[{\"path\":\"../x\",\"address\":\"$INTRO\"},{\"path\":\"y\"}]}"
# {"error":"Bad request: 2 invalid entries: entries[0]: invalid path \"../x\": path component \"..\" is not allowed; entries[1]: needs a data_map or an address","code":"BAD_REQUEST"}
```

The full route list is in the Manifests section of [llms-full.txt](../llms-full.txt).

## Next Steps

- [Tutorial: Store and Retrieve Data](tutorial-store-retrieve.md): the public and private uploads a manifest lists
- [Tutorial: Point at a Public File and Update It](tutorial-pointers.md): an address you can move, for a "latest version" of a manifest's files
- [Architecture Guide](architecture.md): the full data model
- Each SDK has a runnable manifests example: `ant dev example manifests -l <language>` (see the [README](../README.md#manifests) for the file in each SDK)
