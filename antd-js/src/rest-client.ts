import { discoverDaemonUrl } from "./discover.js";
import { fromHttpStatus, NetworkError } from "./errors.js";
import type {
  FinalizeUploadResult,
  HealthStatus,
  PaymentInfo,
  PrepareUploadResult,
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
    } catch (err: unknown) {
      if (err instanceof DOMException && err.name === "AbortError") {
        throw new NetworkError(`request timed out after ${this.timeout}ms`);
      }
      const msg = err instanceof Error ? err.message : String(err);
      throw new NetworkError(msg);
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

  async fileCost(
    path: string,
    isPublic: boolean = true,
  ): Promise<string> {
    const j = await this.postJson<{ cost: string }>("/v1/cost/file", {
      path,
      is_public: isPublic,
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

  /** Approve the wallet to spend tokens on payment contracts (one-time operation). */
  async walletApprove(): Promise<boolean> {
    const j = await this.postJson<{ approved: boolean }>("/v1/wallet/approve", {});
    return j.approved;
  }

  // ---- External Signer (Two-Phase Upload) ----

  /** Prepare a file upload for external signing. */
  async prepareUpload(path: string): Promise<PrepareUploadResult> {
    const j = await this.postJson<{
      upload_id: string;
      payments: { quote_hash: string; rewards_address: string; amount: string }[];
      total_amount: string;
      data_payments_address: string;
      payment_token_address: string;
      rpc_url: string;
    }>("/v1/upload/prepare", { path });
    return {
      uploadId: j.upload_id,
      payments: (j.payments ?? []).map((p) => ({
        quoteHash: p.quote_hash,
        rewardsAddress: p.rewards_address,
        amount: p.amount,
      })),
      totalAmount: j.total_amount,
      dataPaymentsAddress: j.data_payments_address,
      paymentTokenAddress: j.payment_token_address,
      rpcUrl: j.rpc_url,
    };
  }

  /** Prepare a data upload for external signing. */
  async prepareDataUpload(data: Buffer): Promise<PrepareUploadResult> {
    const j = await this.postJson<{
      upload_id: string;
      payments: { quote_hash: string; rewards_address: string; amount: string }[];
      total_amount: string;
      data_payments_address: string;
      payment_token_address: string;
      rpc_url: string;
    }>("/v1/data/prepare", { data: RestClient.b64(data) });
    return {
      uploadId: j.upload_id,
      payments: (j.payments ?? []).map((p) => ({
        quoteHash: p.quote_hash,
        rewardsAddress: p.rewards_address,
        amount: p.amount,
      })),
      totalAmount: j.total_amount,
      dataPaymentsAddress: j.data_payments_address,
      paymentTokenAddress: j.payment_token_address,
      rpcUrl: j.rpc_url,
    };
  }

  /** Finalize an upload after an external signer has submitted payment transactions. */
  async finalizeUpload(
    uploadId: string,
    txHashes: Record<string, string>,
  ): Promise<FinalizeUploadResult> {
    const j = await this.postJson<{ address: string; chunks_stored: number }>(
      "/v1/upload/finalize",
      { upload_id: uploadId, tx_hashes: txHashes },
    );
    return { address: j.address, chunksStored: j.chunks_stored };
  }
}
