import { fromHttpStatus } from "./errors.js";
import type {
  Archive,
  ArchiveEntry,
  GraphDescendant,
  GraphEntry,
  HealthStatus,
  Pointer,
  PointerTarget,
  PutResult,
  Register,
  Scratchpad,
  Vault,
} from "./models.js";

/** Options for creating a REST client. */
export interface RestClientOptions {
  /** Base URL of the antd daemon. Defaults to "http://localhost:8080". */
  baseUrl?: string;
  /** Request timeout in milliseconds. Defaults to 300000 (5 minutes). */
  timeout?: number;
}

/** REST client for the antd daemon. */
export class RestClient {
  private readonly baseUrl: string;
  private readonly timeout: number;

  constructor(options: RestClientOptions = {}) {
    this.baseUrl = (options.baseUrl ?? "http://localhost:8080").replace(/\/+$/, "");
    this.timeout = options.timeout ?? 300_000;
  }

  // ---- internal helpers ----

  private async request(
    method: string,
    path: string,
    options?: { json?: unknown; params?: Record<string, string> },
  ): Promise<Response> {
    let url = `${this.baseUrl}${path}`;
    if (options?.params) {
      const qs = new URLSearchParams(options.params);
      url += `?${qs.toString()}`;
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeout);

    try {
      const resp = await fetch(url, {
        method,
        headers: options?.json !== undefined ? { "Content-Type": "application/json" } : undefined,
        body: options?.json !== undefined ? JSON.stringify(options.json) : undefined,
        signal: controller.signal,
      });
      return resp;
    } finally {
      clearTimeout(timer);
    }
  }

  private async check(resp: Response): Promise<void> {
    if (resp.ok) return;
    let msg: string;
    try {
      const body = await resp.json();
      msg = (body as Record<string, string>).error ?? resp.statusText;
    } catch {
      msg = resp.statusText;
    }
    throw fromHttpStatus(resp.status, msg);
  }

  private async getJson<T>(path: string, params?: Record<string, string>): Promise<T> {
    const resp = await this.request("GET", path, { params });
    await this.check(resp);
    return (await resp.json()) as T;
  }

  private async postJson<T>(path: string, body: unknown): Promise<T> {
    const resp = await this.request("POST", path, { json: body });
    await this.check(resp);
    return (await resp.json()) as T;
  }

  private async putJson<T>(path: string, body: unknown): Promise<T> {
    const resp = await this.request("PUT", path, { json: body });
    await this.check(resp);
    return (await resp.json()) as T;
  }

  private async putJsonNoResult(path: string, body: unknown): Promise<void> {
    const resp = await this.request("PUT", path, { json: body });
    await this.check(resp);
  }

  private async postJsonNoResult(path: string, body: unknown): Promise<void> {
    const resp = await this.request("POST", path, { json: body });
    await this.check(resp);
  }

  private async headExists(path: string): Promise<boolean> {
    const resp = await this.request("HEAD", path);
    if (resp.status === 404) return false;
    await this.check(resp);
    return true;
  }

  private static b64(data: Buffer): string {
    return data.toString("base64");
  }

  private static unb64(s: string): Buffer {
    return Buffer.from(s, "base64");
  }

  // ---- Health ----

  async health(): Promise<HealthStatus> {
    const j = await this.getJson<{ status: string; network: string }>("/health");
    return { ok: j.status === "ok", network: j.network ?? "unknown" };
  }

  // ---- Data ----

  async dataPutPublic(data: Buffer): Promise<PutResult> {
    const j = await this.postJson<{ cost: string; address: string }>("/v1/data/public", {
      data: RestClient.b64(data),
    });
    return { cost: j.cost, address: j.address };
  }

  async dataGetPublic(address: string): Promise<Buffer> {
    const j = await this.getJson<{ data: string }>(`/v1/data/public/${address}`);
    return RestClient.unb64(j.data);
  }

  async dataPutPrivate(data: Buffer): Promise<PutResult> {
    const j = await this.postJson<{ cost: string; data_map: string }>("/v1/data/private", {
      data: RestClient.b64(data),
    });
    return { cost: j.cost, address: j.data_map };
  }

  async dataGetPrivate(dataMap: string): Promise<Buffer> {
    const j = await this.getJson<{ data: string }>("/v1/data/private", { data_map: dataMap });
    return RestClient.unb64(j.data);
  }

  async dataCost(data: Buffer): Promise<string> {
    const j = await this.postJson<{ cost: string }>("/v1/data/cost", {
      data: RestClient.b64(data),
    });
    return j.cost;
  }

  // ---- Chunks ----

  async chunkPut(data: Buffer): Promise<PutResult> {
    const j = await this.postJson<{ cost: string; address: string }>("/v1/chunks", {
      data: RestClient.b64(data),
    });
    return { cost: j.cost, address: j.address };
  }

  async chunkGet(address: string): Promise<Buffer> {
    const j = await this.getJson<{ data: string }>(`/v1/chunks/${address}`);
    return RestClient.unb64(j.data);
  }

  // ---- Pointers ----

  async pointerCreate(ownerSecretKey: string, target: PointerTarget): Promise<PutResult> {
    const j = await this.postJson<{ cost: string; address: string }>("/v1/pointers", {
      owner_secret_key: ownerSecretKey,
      target: { kind: target.kind, address: target.address },
    });
    return { cost: j.cost, address: j.address };
  }

  async pointerGet(address: string): Promise<Pointer> {
    const j = await this.getJson<{
      address: string;
      owner: string;
      counter: number;
      target: { kind: string; address: string };
    }>(`/v1/pointers/${address}`);
    return {
      address: j.address,
      owner: j.owner,
      counter: j.counter,
      target: {
        kind: j.target.kind as PointerTarget["kind"],
        address: j.target.address,
      },
    };
  }

  async pointerExists(address: string): Promise<boolean> {
    return this.headExists(`/v1/pointers/${address}`);
  }

  async pointerUpdate(ownerSecretKey: string, target: PointerTarget): Promise<void> {
    await this.putJsonNoResult(`/v1/pointers/${ownerSecretKey}`, {
      owner_secret_key: ownerSecretKey,
      target: { kind: target.kind, address: target.address },
    });
  }

  async pointerCost(publicKey: string): Promise<string> {
    const j = await this.postJson<{ cost: string }>("/v1/pointers/cost", {
      public_key: publicKey,
    });
    return j.cost;
  }

  // ---- Scratchpads ----

  async scratchpadCreate(
    ownerSecretKey: string,
    contentType: number,
    data: Buffer,
  ): Promise<PutResult> {
    const j = await this.postJson<{ cost: string; address: string }>("/v1/scratchpads", {
      owner_secret_key: ownerSecretKey,
      content_type: contentType,
      data: RestClient.b64(data),
    });
    return { cost: j.cost, address: j.address };
  }

  async scratchpadGet(address: string): Promise<Scratchpad> {
    const j = await this.getJson<{
      address: string;
      data_encoding: number;
      data: string;
      counter: number;
    }>(`/v1/scratchpads/${address}`);
    return {
      address: j.address,
      dataEncoding: j.data_encoding,
      data: RestClient.unb64(j.data),
      counter: j.counter,
    };
  }

  async scratchpadExists(address: string): Promise<boolean> {
    return this.headExists(`/v1/scratchpads/${address}`);
  }

  async scratchpadUpdate(
    ownerSecretKey: string,
    contentType: number,
    data: Buffer,
  ): Promise<void> {
    await this.putJsonNoResult(`/v1/scratchpads/${ownerSecretKey}`, {
      owner_secret_key: ownerSecretKey,
      content_type: contentType,
      data: RestClient.b64(data),
    });
  }

  async scratchpadCost(publicKey: string): Promise<string> {
    const j = await this.postJson<{ cost: string }>("/v1/scratchpads/cost", {
      public_key: publicKey,
    });
    return j.cost;
  }

  // ---- Graph ----

  async graphEntryPut(
    ownerSecretKey: string,
    parents: string[],
    content: string,
    descendants: GraphDescendant[],
  ): Promise<PutResult> {
    const j = await this.postJson<{ cost: string; address: string }>("/v1/graph", {
      owner_secret_key: ownerSecretKey,
      parents,
      content,
      descendants: descendants.map((d) => ({
        public_key: d.publicKey,
        content: d.content,
      })),
    });
    return { cost: j.cost, address: j.address };
  }

  async graphEntryGet(address: string): Promise<GraphEntry> {
    const j = await this.getJson<{
      owner: string;
      parents?: string[];
      content: string;
      descendants?: { public_key: string; content: string }[];
    }>(`/v1/graph/${address}`);
    return {
      owner: j.owner,
      parents: j.parents ?? [],
      content: j.content,
      descendants: (j.descendants ?? []).map((d) => ({
        publicKey: d.public_key,
        content: d.content,
      })),
    };
  }

  async graphEntryExists(address: string): Promise<boolean> {
    return this.headExists(`/v1/graph/${address}`);
  }

  async graphEntryCost(publicKey: string): Promise<string> {
    const j = await this.postJson<{ cost: string }>("/v1/graph/cost", {
      public_key: publicKey,
    });
    return j.cost;
  }

  // ---- Registers ----

  async registerCreate(ownerSecretKey: string, initialValue: string): Promise<PutResult> {
    const j = await this.postJson<{ cost: string; address: string }>("/v1/registers", {
      owner_secret_key: ownerSecretKey,
      initial_value: initialValue,
    });
    return { cost: j.cost, address: j.address };
  }

  async registerGet(address: string): Promise<Register> {
    const j = await this.getJson<{ value: string }>(`/v1/registers/${address}`);
    return { value: j.value };
  }

  async registerUpdate(ownerSecretKey: string, newValue: string): Promise<PutResult> {
    const j = await this.putJson<{ cost: string }>(`/v1/registers/${ownerSecretKey}`, {
      owner_secret_key: ownerSecretKey,
      new_value: newValue,
    });
    return { cost: j.cost, address: "" };
  }

  async registerCost(publicKey: string): Promise<string> {
    const j = await this.postJson<{ cost: string }>("/v1/registers/cost", {
      public_key: publicKey,
    });
    return j.cost;
  }

  // ---- Vaults ----

  async vaultGet(secretKey: string): Promise<Vault> {
    const j = await this.getJson<{ data: string; content_type: number }>("/v1/vaults", {
      secret_key: secretKey,
    });
    return { data: RestClient.unb64(j.data), contentType: j.content_type };
  }

  async vaultPut(secretKey: string, data: Buffer, contentType: number): Promise<string> {
    const j = await this.postJson<{ cost: string }>("/v1/vaults", {
      secret_key: secretKey,
      data: RestClient.b64(data),
      content_type: contentType,
    });
    return j.cost;
  }

  async vaultCost(secretKey: string, maxSize: number): Promise<string> {
    const j = await this.postJson<{ cost: string }>("/v1/vaults/cost", {
      secret_key: secretKey,
      max_size: maxSize,
    });
    return j.cost;
  }

  // ---- Files ----

  async fileUploadPublic(path: string): Promise<PutResult> {
    const j = await this.postJson<{ cost: string; address: string }>("/v1/files/upload/public", {
      path,
    });
    return { cost: j.cost, address: j.address };
  }

  async fileDownloadPublic(address: string, destPath: string): Promise<void> {
    await this.postJsonNoResult("/v1/files/download/public", {
      address,
      dest_path: destPath,
    });
  }

  async dirUploadPublic(path: string): Promise<PutResult> {
    const j = await this.postJson<{ cost: string; address: string }>("/v1/dirs/upload/public", {
      path,
    });
    return { cost: j.cost, address: j.address };
  }

  async dirDownloadPublic(address: string, destPath: string): Promise<void> {
    await this.postJsonNoResult("/v1/dirs/download/public", {
      address,
      dest_path: destPath,
    });
  }

  async archiveGetPublic(address: string): Promise<Archive> {
    const j = await this.getJson<{
      entries?: { path: string; address: string; created: number; modified: number; size: number }[];
    }>(`/v1/archives/public/${address}`);
    const entries: ArchiveEntry[] = (j.entries ?? []).map((e) => ({
      path: e.path,
      address: e.address,
      created: e.created,
      modified: e.modified,
      size: e.size,
    }));
    return { entries };
  }

  async archivePutPublic(archive: Archive): Promise<PutResult> {
    const j = await this.postJson<{ cost: string; address: string }>("/v1/archives/public", {
      entries: archive.entries.map((e) => ({
        path: e.path,
        address: e.address,
        created: e.created,
        modified: e.modified,
        size: e.size,
      })),
    });
    return { cost: j.cost, address: j.address };
  }

  async fileCost(
    path: string,
    isPublic: boolean = true,
    includeArchive: boolean = false,
  ): Promise<string> {
    const j = await this.postJson<{ cost: string }>("/v1/cost/file", {
      path,
      is_public: isPublic,
      include_archive: includeArchive,
    });
    return j.cost;
  }
}
