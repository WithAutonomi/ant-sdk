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

### Files

| Method | Returns | Description |
|--------|---------|-------------|
| `fileUploadPublic(path)` | `PutResult` | Upload file |
| `fileDownloadPublic(address, destPath)` | `void` | Download file |
| `dirUploadPublic(path)` | `PutResult` | Upload directory |
| `dirDownloadPublic(address, destPath)` | `void` | Download directory |
| `fileCost(path, isPublic?)` | `string` | Estimate upload cost |

## Models

```typescript
interface HealthStatus { ok: boolean; network: string }
interface PutResult { cost: string; address: string }
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

The `examples/` directory contains 6 runnable scripts covering all major features:

| Example | Description |
|---------|-------------|
| `01-connect.ts` | Health check |
| `02-data.ts` | Public data store/retrieve |
| `03-chunks.ts` | Raw chunk operations |
| `04-files.ts` | File upload/download |
| `06-private-data.ts` | Private encrypted data |

Run examples with [tsx](https://github.com/privatenumber/tsx):

```bash
npx tsx examples/01-connect.ts
```

## License

See repository root for license information.
