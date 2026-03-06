# Architecture Guide

This document explains the Autonomi network mental model, how ant-sdk fits in, and the key concepts you need to build applications.

## What is Autonomi?

Autonomi is a decentralized, peer-to-peer data network. Instead of storing data on a central server (AWS, GCP, etc.), your data is distributed across a global mesh of nodes. Key properties:

- **Content-addressed**: Immutable data is identified by its cryptographic hash. The same content always produces the same address.
- **Owner-addressed**: Mutable data (pointers, registers, scratchpads) is tied to a cryptographic key pair. Only the owner can update it.
- **Self-encrypting**: Private data is encrypted before storage — the network never sees plaintext.
- **Permanent**: Once data is stored, it persists as long as the network exists. There are no monthly bills or expiring storage.
- **Pay-once**: You pay a one-time storage fee in network tokens. No ongoing costs.

## Where ant-sdk Fits

```
Your Application
       │
       │  Python / C# / Kotlin / Swift SDK calls
       ▼
   ┌───────┐
   │ antd  │   Local daemon process
   │       │   REST API (:8080) + gRPC (:50051)
   └───┬───┘
       │
       │  Autonomi client library (Rust)
       ▼
   ┌───────────────┐
   │   Autonomi    │   Decentralized P2P network
   │   Network     │   Thousands of nodes worldwide
   └───────────────┘
```

**antd** is a local gateway daemon. It:

1. Maintains a connection to the Autonomi network
2. Manages your wallet for payments
3. Exposes a clean REST + gRPC API
4. Handles serialization, encryption, chunking, and payment negotiation

Your application code never touches the network directly. You call `client.data_put_public(data)` and antd handles everything.

## Data Primitives

### Immutable Data

#### Data (Public & Private)

The simplest primitive. Store arbitrary bytes, get back an address.

```
Store:    bytes  ──▶  antd  ──▶  address (hex)
Retrieve: address ──▶  antd  ──▶  bytes
```

- **Public**: Anyone with the address can read it.
- **Private**: Data is self-encrypted. You get back a "data map" (encrypted metadata) instead of a raw address. Only someone with the data map can decrypt and read the original data.

Use for: documents, images, configuration snapshots, backups.

#### Chunks

Low-level content-addressed storage. Data is the raw chunk — one block on the network. Most applications should use the higher-level Data API instead, which handles chunking large payloads automatically.

Use for: custom chunking strategies, direct network interaction.

#### Files & Archives

Upload/download local files and directories. Under the hood, files are chunked and stored as Data, with an Archive manifest that maps paths to addresses.

```
Upload:    local path  ──▶  antd  ──▶  archive address
Download:  address     ──▶  antd  ──▶  local path
```

Use for: file hosting, static websites, media storage.

### Mutable Data

All mutable primitives are **owner-controlled** — you provide a secret key to create and update them. The secret key derives a public key, which determines the resource's network address.

#### Pointers

A pointer is a mutable reference to another resource. Think of it as a DNS record for the network.

```
Pointer (owned by key K)
  └── points to: chunk @ 0xabc123...

Update pointer:
  └── now points to: chunk @ 0xdef456...
```

- **Versioned**: Each update increments a counter. The network always returns the latest version.
- **Target types**: Can point to chunks, graph entries, other pointers, or scratchpads.

Use for: mutable URLs, latest-version references, aliases.

#### Scratchpads

Versioned mutable storage. Like a pointer, but instead of referencing another resource, it stores data directly.

```
Scratchpad (owned by key K)
  ├── counter: 3
  ├── content_type: 1
  └── data: <encrypted bytes>
```

- **Counter**: Monotonically increasing version number.
- **Content type**: Integer tag for your application's encoding scheme.
- **Data**: Raw bytes (encrypted on the network).

Use for: user profiles, settings, mutable application state.

#### Registers

A 32-byte mutable value. The simplest mutable primitive.

```
Register (owned by key K)
  └── value: 0x0000...0000 (32 bytes, hex-encoded)
```

Use for: counters, flags, small state values, hash pointers.

#### Vaults

Private encrypted key-value storage. Unlike other primitives, vaults are accessed by secret key alone (not by network address).

```
Vault (accessed by secret key S)
  ├── content_type: 42
  └── data: <encrypted bytes>
```

Use for: user secrets, encrypted settings, private application data.

### Append-Only Data

#### Graph Entries

DAG (Directed Acyclic Graph) nodes. Each entry has an owner, content, parent links, and descendant links.

```
GraphEntry (owned by key K)
  ├── content: 0x... (32 bytes)
  ├── parents: [addr1, addr2]
  └── descendants: [{public_key, content}, ...]
```

Use for: linked data structures, version history, social graphs, dependency trees.

## Payment Model

Every write operation costs network tokens (measured in "atto tokens" — 1 token = 10^18 atto).

```python
# Estimate before committing
cost = client.data_cost(data)
print(f"This will cost {cost} atto tokens")

# The actual write returns the real cost
result = client.data_put_public(data)
print(f"Paid {result.cost} atto tokens")
```

- **Cost estimation**: All write operations have a corresponding `*_cost` method.
- **One-time payment**: You pay once. Data persists forever.
- **Reads are free**: Retrieving data doesn't cost tokens.
- **Local testnet**: The EVM testnet provides unlimited funds for development.

## Content Addressing vs Cloud Storage

| Aspect | Cloud (S3, etc.) | Autonomi |
|--------|-------------------|----------|
| Addressing | Arbitrary keys | Content hash (immutable) or owner key (mutable) |
| Persistence | Until you stop paying | Permanent (one-time payment) |
| Access control | IAM policies | Cryptographic keys |
| Redundancy | Configurable | Built-in (network-wide replication) |
| Privacy | Trust the provider | Self-encrypting (zero knowledge) |
| Mutability | Overwrite anything | Explicit mutable types (pointers, registers, etc.) |
| Cost model | Per-request + storage/month | One-time write fee, reads are free |

## Key Design Patterns

### Pattern 1: Immutable Data + Mutable Pointer

Store immutable versions of your data, then use a pointer to track the latest version.

```python
# Store v1
v1 = client.data_put_public(b"config v1")

# Create a pointer to v1
from antd import PointerTarget
target = PointerTarget(kind="chunk", address=v1.address)
ptr = client.pointer_create(secret_key, target)

# Later: store v2 and update the pointer
v2 = client.data_put_public(b"config v2")
new_target = PointerTarget(kind="chunk", address=v2.address)
client.pointer_update(secret_key, new_target)

# Anyone with the pointer address always gets the latest version
current = client.pointer_get(ptr.address)
data = client.data_get_public(current.target.address)
```

### Pattern 2: Versioned State with Scratchpads

Use scratchpads for state that changes frequently and where you want version tracking.

```python
# Create a scratchpad
import json
config = json.dumps({"theme": "dark"}).encode()
pad = client.scratchpad_create(secret_key, content_type=1, data=config)

# Update it
new_config = json.dumps({"theme": "light"}).encode()
client.scratchpad_update(secret_key, content_type=1, data=new_config)

# Read — the counter tells you which version this is
current = client.scratchpad_get(pad.address)
print(f"Version: {current.counter}")
```

### Pattern 3: Linked History with Graph Entries

Build append-only logs or version chains using graph entries.

```python
import os

# First entry (no parents)
key1 = os.urandom(32).hex()
content1 = os.urandom(32).hex()
entry1 = client.graph_entry_put(key1, parents=[], content=content1, descendants=[])

# Second entry links to the first
key2 = os.urandom(32).hex()
content2 = os.urandom(32).hex()
entry2 = client.graph_entry_put(key2, parents=[entry1.address], content=content2, descendants=[])
```

## Security Model

- **Secret keys**: 32-byte hex-encoded keys. Anyone with the key can update the associated resource.
- **Never share secret keys**: Treat them like passwords. The public key (derived from the secret key) is safe to share.
- **Private data**: Self-encrypted using the network's encryption scheme. The data map is needed for decryption.
- **No access revocation**: Once data is public, it cannot be made private. Once a key is shared, access cannot be revoked. Plan your key management accordingly.
