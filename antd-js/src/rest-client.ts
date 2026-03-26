import { discoverDaemonUrl } from "./discover.js";
import { fromHttpStatus } from "./errors.js";
import type {
  Archive,
  ArchiveEntry,
  GraphDescendant,
  GraphEntry,
  HealthStatus,
  PutResult,
  WalletAddress,
  WalletBalance,
} from "./models.js";

/** Options for creating a REST client. */
export interface RestClientOptions {
  /** Base URL of the antd daemon. Defaults to "http://localhost:8082". */
  baseUrl?: string;
  /** Request timeout in milliseconds. Defaults to 300000 (5 minutes). */
  timeout?: number;
}

/** REST client for the antd daemon. */
export class RestClient {
  private readonly baseUrl: string;
  private readonly timeout: number;

  /**
   * Creates a REST client by auto-discovering the daemon port from the
   * daemon.port file written by antd on startup. Falls back to the default
   * base URL if the port file is not found.
   *
   * @returns An object with the created `client` and the discovered `url`
   *          (empty string if discovery failed and default was used).
   */
  static autoDiscover(options?: RestClientOptions): { client: RestClient; url: string } {
    const discovered = discoverDaemonUrl();
    const opts: RestClientOptions = { ...options };
    if (discovered !== "") {
      opts.baseUrl = discovered;
    }
    return { client: new RestClient(opts), url: discovered };
  }

  constructor(options: RestClientOptions = {}) {
    this.baseUrl = (options.baseUrl ?? "http://localhost:8082").replace(/\/+$/, "");
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

  async dataPutPublic(data: Buffer, options?: { paymentMode?: string }): Promise<PutResult> {
    const body: Record<string, unknown> = { data: RestClient.b64(data) };
    if (options?.paymentMode) body.payment_mode = options.paymentMode;
    const j = await this.postJson<{ cost: string; address: string }>("/v1/data/public", body);
    return { cost: j.cost, address: j.address };
  }

  async dataGetPublic(address: string): Promise<Buffer> {
    const j = await this.getJson<{ data: string }>(`/v1/data/public/${address}`);
    return RestClient.unb64(j.data);
  }

  async dataPutPrivate(data: Buffer, options?: { paymentMode?: string }): Promise<PutResult> {
    const body: Record<string, unknown> = { data: RestClient.b64(data) };
    if (options?.paymentMode) body.payment_mode = options.paymentMode;
    const j = await this.postJson<{ cost: string; data_map: string }>("/v1/data/private", body);
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

  // ---- Files ----

  async fileUploadPublic(path: string, options?: { paymentMode?: string }): Promise<PutResult> {
    const body: Record<string, unknown> = { path };
    if (options?.paymentMode) body.payment_mode = options.paymentMode;
    const j = await this.postJson<{ cost: string; address: string }>("/v1/files/upload/public", body);
    return { cost: j.cost, address: j.address };
  }

  async fileDownloadPublic(address: string, destPath: string): Promise<void> {
    await this.postJsonNoResult("/v1/files/download/public", {
      address,
      dest_path: destPath,
    });
  }

  async dirUploadPublic(path: string, options?: { paymentMode?: string }): Promise<PutResult> {
    const body: Record<string, unknown> = { path };
    if (options?.paymentMode) body.payment_mode = options.paymentMode;
    const j = await this.postJson<{ cost: string; address: string }>("/v1/dirs/upload/public", body);
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

  // ---- Wallet ----

  async walletAddress(): Promise<WalletAddress> {
    const j = await this.getJson<{ address: string }>("/v1/wallet/address");
    return { address: j.address };
  }

  async walletBalance(): Promise<WalletBalance> {
    const j = await this.getJson<{ balance: string; gas_balance: string }>("/v1/wallet/balance");
    return { balance: j.balance, gasBalance: j.gas_balance };
  }
}
