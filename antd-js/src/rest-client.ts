import { discoverDaemonUrl } from "./discover.js";
import { fromHttpStatus, NetworkError } from "./errors.js";
import { PaymentMode } from "./models.js";
import type {
  DataPutPublicResult,
  DataPutResult,
  FilePutPublicResult,
  FilePutResult,
  FinalizeUploadResult,
  HealthStatus,
  PrepareChunkResult,
  PrepareUploadResult,
  PutResult,
  UploadCostEstimate,
  WalletAddress,
  WalletBalance,
} from "./models.js";

/** Wire shape of the antd /health response. All diagnostic fields are
 * optional so we can still parse responses from a pre-0.4.0 daemon. */
interface HealthJson {
  status?: string;
  network?: string;
  version?: string;
  evm_network?: string;
  uptime_seconds?: number;
  build_commit?: string;
  payment_token_address?: string;
  payment_vault_address?: string;
}

/** Convert a /health JSON response to a typed HealthStatus. Diagnostic fields
 * default to empty/zero when talking to a pre-0.4.0 daemon. */
export function healthStatusFromJson(j: HealthJson): HealthStatus {
  return {
    ok: j.status === "ok",
    network: j.network ?? "unknown",
    version: j.version ?? "",
    evmNetwork: j.evm_network ?? "",
    uptimeSeconds: j.uptime_seconds ?? 0,
    buildCommit: j.build_commit ?? "",
    paymentTokenAddress: j.payment_token_address ?? "",
    paymentVaultAddress: j.payment_vault_address ?? "",
  };
}

/** Options for creating a REST client. */
export interface RestClientOptions {
  /** Base URL of the antd daemon. Defaults to "http://localhost:8082". */
  baseUrl?: string;
  /** Request timeout in milliseconds. Defaults to 300000 (5 minutes). */
  timeout?: number;
}

/**
 * REST client for the antd daemon.
 *
 * Naming convention (post v1.0):
 *   - Unqualified verb (`dataPut`, `dataGet`, `filePut`, `fileGet`) = private —
 *     the DataMap is returned to the caller and NOT stored on-network.
 *   - `_public` suffix = public — the DataMap is stored on-network as an
 *     extra chunk; the call returns the shareable address.
 */
export class RestClient {
  private readonly baseUrl: string;
  private readonly timeout: number;

  /**
   * Creates a REST client by auto-discovering the daemon port from the
   * daemon.port file written by antd on startup. Falls back to the default
   * base URL if the port file is not found.
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

  private static b64(data: Buffer): string {
    return data.toString("base64");
  }

  private static unb64(s: string): Buffer {
    return Buffer.from(s, "base64");
  }

  // ---- Health ----

  async health(): Promise<HealthStatus> {
    const j = await this.getJson<HealthJson>("/health");
    return healthStatusFromJson(j);
  }

  // ---- Data ----

  async dataPutPublic(
    data: Buffer,
    options?: { paymentMode?: PaymentMode },
  ): Promise<DataPutPublicResult> {
    const body = {
      data: RestClient.b64(data),
      payment_mode: options?.paymentMode ?? PaymentMode.Auto,
    };
    const j = await this.postJson<{
      address: string;
      chunks_stored?: number;
      payment_mode_used?: string;
    }>("/v1/data/public", body);
    return {
      address: j.address,
      chunksStored: j.chunks_stored ?? 0,
      paymentModeUsed: j.payment_mode_used ?? "",
    };
  }

  async dataGetPublic(address: string): Promise<Buffer> {
    const j = await this.getJson<{ data: string }>(`/v1/data/public/${address}`);
    return RestClient.unb64(j.data);
  }

  async dataPut(
    data: Buffer,
    options?: { paymentMode?: PaymentMode },
  ): Promise<DataPutResult> {
    const body = {
      data: RestClient.b64(data),
      payment_mode: options?.paymentMode ?? PaymentMode.Auto,
    };
    const j = await this.postJson<{
      data_map: string;
      chunks_stored?: number;
      payment_mode_used?: string;
    }>("/v1/data", body);
    return {
      dataMap: j.data_map,
      chunksStored: j.chunks_stored ?? 0,
      paymentModeUsed: j.payment_mode_used ?? "",
    };
  }

  async dataGet(dataMap: string): Promise<Buffer> {
    const j = await this.postJson<{ data: string }>("/v1/data/get", { data_map: dataMap });
    return RestClient.unb64(j.data);
  }

  /**
   * Pre-upload cost breakdown for the given bytes.
   *
   * The server samples a small number of chunk addresses and extrapolates,
   * much faster than quoting every chunk on slow networks. Gas is advisory.
   */
  async dataCost(
    data: Buffer,
    options?: { paymentMode?: PaymentMode },
  ): Promise<UploadCostEstimate> {
    const j = await this.postJson<{
      cost: string;
      file_size: number;
      chunk_count: number;
      estimated_gas_cost_wei: string;
      payment_mode: string;
    }>("/v1/data/cost", {
      data: RestClient.b64(data),
      payment_mode: options?.paymentMode ?? PaymentMode.Auto,
    });
    return {
      cost: j.cost,
      fileSize: j.file_size,
      chunkCount: j.chunk_count,
      estimatedGasCostWei: j.estimated_gas_cost_wei,
      paymentMode: j.payment_mode,
    };
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

  async filePutPublic(
    path: string,
    options?: { paymentMode?: PaymentMode },
  ): Promise<FilePutPublicResult> {
    const body = {
      path,
      payment_mode: options?.paymentMode ?? PaymentMode.Auto,
    };
    const j = await this.postJson<{
      address: string;
      storage_cost_atto: string;
      gas_cost_wei: string;
      chunks_stored: number;
      payment_mode_used: string;
    }>("/v1/files/public", body);
    return {
      address: j.address,
      storageCostAtto: j.storage_cost_atto,
      gasCostWei: j.gas_cost_wei,
      chunksStored: j.chunks_stored,
      paymentModeUsed: j.payment_mode_used,
    };
  }

  async fileGetPublic(address: string, destPath: string): Promise<void> {
    await this.postJsonNoResult("/v1/files/public/get", {
      address,
      dest_path: destPath,
    });
  }

  async filePut(
    path: string,
    options?: { paymentMode?: PaymentMode },
  ): Promise<FilePutResult> {
    const body = {
      path,
      payment_mode: options?.paymentMode ?? PaymentMode.Auto,
    };
    const j = await this.postJson<{
      data_map: string;
      storage_cost_atto: string;
      gas_cost_wei: string;
      chunks_stored: number;
      payment_mode_used: string;
    }>("/v1/files", body);
    return {
      dataMap: j.data_map,
      storageCostAtto: j.storage_cost_atto,
      gasCostWei: j.gas_cost_wei,
      chunksStored: j.chunks_stored,
      paymentModeUsed: j.payment_mode_used,
    };
  }

  async fileGet(dataMap: string, destPath: string): Promise<void> {
    await this.postJsonNoResult("/v1/files/get", {
      data_map: dataMap,
      dest_path: destPath,
    });
  }

  /**
   * Pre-upload cost breakdown for the file at `path`.
   *
   * The server samples a small number of chunk addresses and extrapolates,
   * much faster than quoting every chunk on slow networks. Gas is advisory.
   */
  async fileCost(
    path: string,
    isPublic: boolean = true,
    options?: { paymentMode?: PaymentMode },
  ): Promise<UploadCostEstimate> {
    const j = await this.postJson<{
      cost: string;
      file_size: number;
      chunk_count: number;
      estimated_gas_cost_wei: string;
      payment_mode: string;
    }>("/v1/files/cost", {
      path,
      is_public: isPublic,
      payment_mode: options?.paymentMode ?? PaymentMode.Auto,
    });
    return {
      cost: j.cost,
      fileSize: j.file_size,
      chunkCount: j.chunk_count,
      estimatedGasCostWei: j.estimated_gas_cost_wei,
      paymentMode: j.payment_mode,
    };
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

  /**
   * Prepare a file upload for external signing.
   *
   * @param path - Path to the file to upload.
   * @param options - Optional settings.
   * @param options.visibility - `"public"` bundles the DataMap chunk into the
   *   same external-signer payment batch (the resulting `dataMapAddress` on
   *   finalize is the shareable retrieval handle). `"private"` or omitted
   *   keeps the existing private-only behaviour.
   */
  async prepareUpload(
    path: string,
    options?: { visibility?: "public" | "private" },
  ): Promise<PrepareUploadResult> {
    const body: Record<string, unknown> = { path };
    if (options?.visibility !== undefined) body.visibility = options.visibility;
    const j = await this.postJson<{
      upload_id: string;
      payments: { quote_hash: string; rewards_address: string; amount: string }[];
      total_amount: string;
      payment_vault_address: string;
      payment_token_address: string;
      rpc_url: string;
      payment_type?: string;
      depth?: number;
      pool_commitments?: { pool_hash: string; candidates: { rewards_address: string; amount: string }[] }[];
      merkle_payment_timestamp?: number;
      total_chunks?: number;
      already_stored_count?: number;
    }>("/v1/upload/prepare", body);
    const result: PrepareUploadResult = {
      uploadId: j.upload_id,
      payments: (j.payments ?? []).map((p) => ({
        quoteHash: p.quote_hash,
        rewardsAddress: p.rewards_address,
        amount: p.amount,
      })),
      totalAmount: j.total_amount,
      paymentVaultAddress: j.payment_vault_address,
      paymentTokenAddress: j.payment_token_address,
      rpcUrl: j.rpc_url,
      paymentType: j.payment_type ?? "wave_batch",
      totalChunks: j.total_chunks ?? 0,
      alreadyStoredCount: j.already_stored_count ?? 0,
    };
    if (j.depth !== undefined) result.depth = j.depth;
    if (j.pool_commitments !== undefined) {
      result.poolCommitments = j.pool_commitments.map((pc) => ({
        poolHash: pc.pool_hash,
        candidates: pc.candidates.map((c) => ({
          rewardsAddress: c.rewards_address,
          amount: c.amount,
        })),
      }));
    }
    if (j.merkle_payment_timestamp !== undefined) result.merklePaymentTimestamp = j.merkle_payment_timestamp;
    return result;
  }

  /**
   * Convenience wrapper: prepare a *public* file upload for external signing.
   *
   * Equivalent to `prepareUpload(path, { visibility: "public" })`. In addition
   * to the data chunks, the daemon bundles the serialized DataMap chunk into
   * the same payment batch — so the external signer signs ONE EVM transaction
   * covering chunks + DataMap. After `finalizeUpload`, the result's
   * `dataMapAddress` is the shareable retrieval handle.
   *
   * Requires antd >= 0.6.1.
   */
  async prepareUploadPublic(path: string): Promise<PrepareUploadResult> {
    return this.prepareUpload(path, { visibility: "public" });
  }

  /** Prepare a data upload for external signing. */
  async prepareDataUpload(data: Buffer): Promise<PrepareUploadResult> {
    const j = await this.postJson<{
      upload_id: string;
      payments: { quote_hash: string; rewards_address: string; amount: string }[];
      total_amount: string;
      payment_vault_address: string;
      payment_token_address: string;
      rpc_url: string;
      payment_type?: string;
      depth?: number;
      pool_commitments?: { pool_hash: string; candidates: { rewards_address: string; amount: string }[] }[];
      merkle_payment_timestamp?: number;
      total_chunks?: number;
      already_stored_count?: number;
    }>("/v1/data/prepare", { data: RestClient.b64(data) });
    const result: PrepareUploadResult = {
      uploadId: j.upload_id,
      payments: (j.payments ?? []).map((p) => ({
        quoteHash: p.quote_hash,
        rewardsAddress: p.rewards_address,
        amount: p.amount,
      })),
      totalAmount: j.total_amount,
      paymentVaultAddress: j.payment_vault_address,
      paymentTokenAddress: j.payment_token_address,
      rpcUrl: j.rpc_url,
      paymentType: j.payment_type ?? "wave_batch",
      totalChunks: j.total_chunks ?? 0,
      alreadyStoredCount: j.already_stored_count ?? 0,
    };
    if (j.depth !== undefined) result.depth = j.depth;
    if (j.pool_commitments !== undefined) {
      result.poolCommitments = j.pool_commitments.map((pc) => ({
        poolHash: pc.pool_hash,
        candidates: pc.candidates.map((c) => ({
          rewardsAddress: c.rewards_address,
          amount: c.amount,
        })),
      }));
    }
    if (j.merkle_payment_timestamp !== undefined) result.merklePaymentTimestamp = j.merkle_payment_timestamp;
    return result;
  }

  /** Finalize an upload after an external signer has submitted payment transactions. */
  async finalizeUpload(
    uploadId: string,
    txHashes: Record<string, string>,
  ): Promise<FinalizeUploadResult> {
    const j = await this.postJson<{
      address?: string;
      chunks_stored: number;
      data_map?: string;
      data_map_address?: string;
    }>("/v1/upload/finalize", { upload_id: uploadId, tx_hashes: txHashes });
    return {
      address: j.address ?? "",
      chunksStored: j.chunks_stored,
      dataMap: j.data_map ?? "",
      dataMapAddress: j.data_map_address ?? "",
    };
  }

  /** Finalize a merkle batch upload after selecting a winning pool. */
  async finalizeMerkleUpload(
    uploadId: string,
    winnerPoolHash: string,
    storeDataMap = false,
  ): Promise<FinalizeUploadResult> {
    const j = await this.postJson<{
      address?: string;
      chunks_stored: number;
      data_map?: string;
      data_map_address?: string;
    }>("/v1/upload/finalize", {
      upload_id: uploadId,
      winner_pool_hash: winnerPoolHash,
      store_data_map: storeDataMap,
    });
    return {
      address: j.address ?? "",
      chunksStored: j.chunks_stored,
      dataMap: j.data_map ?? "",
      dataMapAddress: j.data_map_address ?? "",
    };
  }

  // ---- Single-chunk external signer (antd >= 0.7.0) ----

  /**
   * Prepare a single chunk for external-signer publish via
   * `POST /v1/chunks/prepare`.
   *
   * The daemon collects storage quotes from the close group, stashes the
   * prepared state, and returns either:
   *
   *   - `alreadyStored: true` with `address` populated — the chunk is already
   *     on-network. No payment or finalize call is needed.
   *   - `alreadyStored: false` with `uploadId` + `payments` + `totalAmount`
   *     populated. The caller signs and submits `payForQuotes()` externally,
   *     then calls `finalizeChunkUpload` with the resulting tx hashes.
   *
   * Unlike `chunkPut`, this method does NOT require the daemon to have a
   * wallet — all funds flow through the external signer.
   *
   * Requires antd >= 0.7.0.
   */
  async prepareChunkUpload(data: Uint8Array | Buffer): Promise<PrepareChunkResult> {
    const buf = Buffer.isBuffer(data) ? data : Buffer.from(data);
    const j = await this.postJson<{
      address: string;
      already_stored: boolean;
      upload_id?: string;
      payment_type?: string;
      payments?: { quote_hash: string; rewards_address: string; amount: string }[];
      total_amount?: string;
      payment_vault_address?: string;
      payment_token_address?: string;
      rpc_url?: string;
    }>("/v1/chunks/prepare", { data: RestClient.b64(buf) });
    return {
      address: j.address,
      alreadyStored: Boolean(j.already_stored),
      uploadId: j.upload_id ?? "",
      paymentType: j.payment_type ?? "",
      payments: (j.payments ?? []).map((p) => ({
        quoteHash: p.quote_hash,
        rewardsAddress: p.rewards_address,
        amount: p.amount,
      })),
      totalAmount: j.total_amount ?? "",
      paymentVaultAddress: j.payment_vault_address ?? "",
      paymentTokenAddress: j.payment_token_address ?? "",
      rpcUrl: j.rpc_url ?? "",
    };
  }

  /**
   * Submit a single chunk to the network after the external signer has paid
   * via `POST /v1/chunks/finalize`.
   *
   * Requires antd >= 0.7.0.
   */
  async finalizeChunkUpload(
    uploadId: string,
    txHashes: Record<string, string>,
  ): Promise<string> {
    const j = await this.postJson<{ address: string }>("/v1/chunks/finalize", {
      upload_id: uploadId,
      tx_hashes: txHashes,
    });
    return j.address;
  }
}
