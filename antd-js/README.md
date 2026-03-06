# antd-js

JavaScript/TypeScript SDK for the [Autonomi](https://autonomi.com) decentralized network via the **antd** daemon.

## Installation

```bash
npm install antd
```

Requires **Node.js 18+** (uses native `fetch`).

## Quick Start

```typescript
import { createClient } from "antd";

const client = createClient(); // default: http://localhost:8080

// Check daemon health
const status = await client.health();
console.log(`Network: ${status.network}`);

// Store and retrieve data
const result = await client.dataPutPublic(Buffer.from("Hello, Autonomi!"));
console.log(`Address: ${result.address}`);

const data = await client.dataGetPublic(result.address);
console.log(data.toString()); // "Hello, Autonomi!"
```

## Client Options

```typescript
import { createClient, RestClient } from "antd";

// Factory function
const client = createClient();
const client = createClient({ baseUrl: "http://remote:8080" });
const client = createClient({ timeout: 60_000 });

// Direct constructor
const client = new RestClient({ baseUrl: "http://localhost:8080", timeout: 300_000 });
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `baseUrl` | `string` | `"http://localhost:8080"` | antd daemon URL |
| `timeout` | `number` | `300000` | Request timeout (ms) |

## API Reference

All methods are `async` and return Promises.

### Health

| Method | Returns | Description |
|--------|---------|-------------|
| `health()` | `HealthStatus` | Check daemon health and network status |

### Data

| Method | Returns | Description |
|--------|---------|-------------|
| `dataPutPublic(data)` | `PutResult` | Store public data |
| `dataGetPublic(address)` | `Buffer` | Retrieve public data by address |
| `dataPutPrivate(data)` | `PutResult` | Store private (encrypted) data |
| `dataGetPrivate(dataMap)` | `Buffer` | Retrieve private data by data map |
| `dataCost(data)` | `string` | Estimate storage cost |

### Chunks

| Method | Returns | Description |
|--------|---------|-------------|
| `chunkPut(data)` | `PutResult` | Store raw chunk |
| `chunkGet(address)` | `Buffer` | Retrieve chunk by address |

### Pointers

| Method | Returns | Description |
|--------|---------|-------------|
| `pointerCreate(ownerSecretKey, target)` | `PutResult` | Create mutable pointer |
| `pointerGet(address)` | `Pointer` | Read pointer |
| `pointerExists(address)` | `boolean` | Check pointer existence |
| `pointerUpdate(ownerSecretKey, target)` | `void` | Update pointer target |
| `pointerCost(publicKey)` | `string` | Estimate creation cost |

### Scratchpads

| Method | Returns | Description |
|--------|---------|-------------|
| `scratchpadCreate(ownerSecretKey, contentType, data)` | `PutResult` | Create versioned scratchpad |
| `scratchpadGet(address)` | `Scratchpad` | Read scratchpad |
| `scratchpadExists(address)` | `boolean` | Check existence |
| `scratchpadUpdate(ownerSecretKey, contentType, data)` | `void` | Update scratchpad |
| `scratchpadCost(publicKey)` | `string` | Estimate creation cost |

### Graph

| Method | Returns | Description |
|--------|---------|-------------|
| `graphEntryPut(ownerSecretKey, parents, content, descendants)` | `PutResult` | Create graph entry |
| `graphEntryGet(address)` | `GraphEntry` | Read graph entry |
| `graphEntryExists(address)` | `boolean` | Check existence |
| `graphEntryCost(publicKey)` | `string` | Estimate creation cost |

### Registers

| Method | Returns | Description |
|--------|---------|-------------|
| `registerCreate(ownerSecretKey, initialValue)` | `PutResult` | Create register |
| `registerGet(address)` | `Register` | Read register value |
| `registerUpdate(ownerSecretKey, newValue)` | `PutResult` | Update register |
| `registerCost(publicKey)` | `string` | Estimate creation cost |

### Vaults

| Method | Returns | Description |
|--------|---------|-------------|
| `vaultGet(secretKey)` | `Vault` | Retrieve vault data |
| `vaultPut(secretKey, data, contentType)` | `string` | Store in vault (returns cost) |
| `vaultCost(secretKey, maxSize)` | `string` | Estimate storage cost |

### Files

| Method | Returns | Description |
|--------|---------|-------------|
| `fileUploadPublic(path)` | `PutResult` | Upload file |
| `fileDownloadPublic(address, destPath)` | `void` | Download file |
| `dirUploadPublic(path)` | `PutResult` | Upload directory |
| `dirDownloadPublic(address, destPath)` | `void` | Download directory |
| `archiveGetPublic(address)` | `Archive` | List archive entries |
| `archivePutPublic(archive)` | `PutResult` | Create archive manifest |
| `fileCost(path, isPublic?, includeArchive?)` | `string` | Estimate upload cost |

## Models

```typescript
interface HealthStatus { ok: boolean; network: string }
interface PutResult { cost: string; address: string }
interface PointerTarget { kind: "chunk" | "graph_entry" | "pointer" | "scratchpad"; address: string }
interface Pointer { address: string; owner: string; counter: number; target: PointerTarget }
interface Scratchpad { address: string; dataEncoding: number; data: Buffer; counter: number }
interface GraphDescendant { publicKey: string; content: string }
interface GraphEntry { owner: string; parents: string[]; content: string; descendants: GraphDescendant[] }
interface Register { value: string }
interface Vault { data: Buffer; contentType: number }
interface ArchiveEntry { path: string; address: string; created: number; modified: number; size: number }
interface Archive { entries: ArchiveEntry[] }
```

## Errors

All errors extend `AntdError`, which extends `Error` and includes a `statusCode` property.

| Error Class | HTTP Status | Description |
|-------------|-------------|-------------|
| `AntdError` | any | Base error class |
| `BadRequestError` | 400 | Invalid request |
| `PaymentError` | 402 | Insufficient wallet funds |
| `NotFoundError` | 404 | Resource not found |
| `AlreadyExistsError` | 409 | Resource already exists |
| `ForkError` | 409 | Version conflict / fork |
| `TooLargeError` | 413 | Data exceeds size limit |
| `InternalError` | 500 | Internal server error |
| `NetworkError` | 502 | Cannot reach network |

```typescript
import { createClient, NotFoundError } from "antd";

const client = createClient();
try {
  await client.dataGetPublic("nonexistent");
} catch (err) {
  if (err instanceof NotFoundError) {
    console.log("Data not found on network");
  }
}
```

## Examples

The `examples/` directory contains 10 runnable scripts covering all major features:

| Example | Description |
|---------|-------------|
| `01-connect.ts` | Health check |
| `02-data.ts` | Public data store/retrieve |
| `03-chunks.ts` | Raw chunk operations |
| `04-files.ts` | File upload/download |
| `05-pointers.ts` | Pointer CRUD |
| `06-scratchpads.ts` | Scratchpad CRUD |
| `07-graph.ts` | Graph entry operations |
| `08-registers.ts` | Register CRUD |
| `09-vaults.ts` | Vault store/retrieve |
| `10-private-data.ts` | Private encrypted data |

Run examples with [tsx](https://github.com/privatenumber/tsx):

```bash
npx tsx examples/01-connect.ts
```

## License

See repository root for license information.
