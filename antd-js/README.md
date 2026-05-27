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

const client = createClient(); // default: http://localhost:8082

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
const client = createClient({ baseUrl: "http://remote:8082" });
const client = createClient({ timeout: 60_000 });

// Direct constructor
const client = new RestClient({ baseUrl: "http://localhost:8082", timeout: 300_000 });
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `baseUrl` | `string` | `"http://localhost:8082"` | antd daemon URL |
| `timeout` | `number` | `300000` | Request timeout (ms) |

## API Reference

All methods are `async` and return Promises.

### Health

| Method | Returns | Description |
|--------|---------|-------------|
| `health()` | `HealthStatus` | Check daemon health — also reports antd version, EVM network, uptime, build commit, and payment contract addresses (antd ≥ 0.4.0) |

### Data

| Method | Returns | Description |
|--------|---------|-------------|
| `dataPutPublic(data, { paymentMode? })` | `DataPutPublicResult` | Store public data — DataMap stored on-network |
| `dataGetPublic(address)` | `Buffer` | Retrieve public data by address |
| `dataPut(data, { paymentMode? })` | `DataPutResult` | Store private (encrypted) data — DataMap returned to caller |
| `dataGet(dataMap)` | `Buffer` | Retrieve private data using a caller-held DataMap |
| `dataCost(data, { paymentMode? })` | `UploadCostEstimate` | Estimate storage cost — size, chunks, gas, payment mode |

### Chunks

| Method | Returns | Description |
|--------|---------|-------------|
| `chunkPut(data)` | `PutResult` | Store raw chunk |
| `chunkGet(address)` | `Buffer` | Retrieve chunk by address |

### Files

| Method | Returns | Description |
|--------|---------|-------------|
| `filePut(path, { paymentMode? })` | `FilePutResult` | Upload a file privately — DataMap returned to caller |
| `fileGet(dataMap, destPath)` | `void` | Download a private file using a caller-held DataMap |
| `filePutPublic(path, { paymentMode? })` | `FilePutPublicResult` | Upload a file publicly — DataMap stored on-network |
| `fileGetPublic(address, destPath)` | `void` | Download a public file by address |
| `fileCost(path, isPublic?, { paymentMode? })` | `UploadCostEstimate` | Estimate upload cost — size, chunks, gas, payment mode |

### External Signer

Two-phase upload — daemon prepares the payment intent, caller signs + submits the payForQuotes tx, daemon finalizes once the chain confirms. See `examples/07-external-signer.ts`.

| Method | Returns | Description |
|--------|---------|-------------|
| `prepareUpload(path, { visibility? })` | `PrepareUploadResult` | Prepare a file upload for external signing |
| `prepareUploadPublic(path)` | `PrepareUploadResult` | Convenience for `prepareUpload(path, { visibility: "public" })` |
| `prepareDataUpload(data)` | `PrepareUploadResult` | Prepare a data upload for external signing |
| `prepareChunkUpload(data)` | `PrepareChunkResult` | Prepare a single chunk for external-signer publish |
| `finalizeUpload(uploadId, txHashes)` | `FinalizeUploadResult` | Submit a prepared upload after external payment. `data_map_address` populated when prepare used `visibility: "public"` |
| `finalizeChunkUpload(uploadId, txHashes)` | `string` | Submit a prepared chunk after external payment; returns the chunk address |

## Models

```typescript
interface HealthStatus {
  ok: boolean;
  network: string;
  version: string;
  evmNetwork: string;
  uptimeSeconds: number;
  buildCommit: string;
  paymentTokenAddress: string;
  paymentVaultAddress: string;
}

// Result of chunkPut only
interface PutResult { cost: string; address: string }

// Data put results (DataMap shape)
interface DataPutResult { dataMap: string; chunksStored: number; paymentModeUsed: string }
interface DataPutPublicResult { address: string; chunksStored: number; paymentModeUsed: string }

// File put results
interface FilePutResult { dataMap: string; storageCostAtto: string; gasCostWei: string; chunksStored: number; paymentModeUsed: string }
interface FilePutPublicResult { address: string; storageCostAtto: string; gasCostWei: string; chunksStored: number; paymentModeUsed: string }

// Cost estimate
interface UploadCostEstimate { cost: string; fileSize: number; chunkCount: number; estimatedGasCostWei: string; paymentMode: string }
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

The `examples/` directory contains 7 runnable scripts covering all major features:

| Example | Description |
|---------|-------------|
| `01-connect.ts` | Health check |
| `02-data.ts` | Public data store/retrieve |
| `03-chunks.ts` | Raw chunk operations |
| `04-files.ts` | File upload/download |
| `06-private-data.ts` | Private encrypted data |
| `07-external-signer.ts` | External-signer file + chunk upload (anvil signer) |

Run examples with [tsx](https://github.com/privatenumber/tsx):

```bash
npx tsx examples/01-connect.ts
```

## License

See repository root for license information.
