using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Antd.Sdk;

public sealed class AntdRestClient : IAntdClient
{
    private readonly HttpClient _http;
    private readonly string _baseUrl;
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public AntdRestClient(string baseUrl = "http://localhost:8082", TimeSpan? timeout = null)
    {
        _baseUrl = baseUrl.TrimEnd('/');
        _http = new HttpClient { BaseAddress = new Uri(_baseUrl), Timeout = timeout ?? TimeSpan.FromSeconds(300) };
    }

    /// <summary>
    /// Creates an AntdRestClient by reading the daemon.port file written by antd.
    /// Falls back to the default base URL if the port file is not found.
    /// </summary>
    public static AntdRestClient AutoDiscover(TimeSpan? timeout = null)
    {
        var url = DaemonDiscovery.DiscoverDaemonUrl();
        return string.IsNullOrEmpty(url) ? new AntdRestClient(timeout: timeout) : new AntdRestClient(url, timeout);
    }

    public void Dispose() => _http.Dispose();

    // ── Helpers ──

    private async Task<T> GetJsonAsync<T>(string path)
    {
        var resp = await _http.GetAsync(path);
        await EnsureSuccessAsync(resp);
        return (await resp.Content.ReadFromJsonAsync<T>(JsonOpts))!;
    }

    private async Task<T> PostJsonAsync<T>(string path, object body)
    {
        var resp = await _http.PostAsJsonAsync(path, body, JsonOpts);
        await EnsureSuccessAsync(resp);
        return (await resp.Content.ReadFromJsonAsync<T>(JsonOpts))!;
    }

    private async Task PostJsonNoResultAsync(string path, object body)
    {
        var resp = await _http.PostAsJsonAsync(path, body, JsonOpts);
        await EnsureSuccessAsync(resp);
    }

    private async Task<bool> HeadExistsAsync(string path)
    {
        var req = new HttpRequestMessage(HttpMethod.Head, path);
        var resp = await _http.SendAsync(req);
        if (resp.StatusCode == HttpStatusCode.NotFound) return false;
        await EnsureSuccessAsync(resp);
        return true;
    }

    private static async Task EnsureSuccessAsync(HttpResponseMessage resp)
    {
        if (resp.IsSuccessStatusCode) return;
        var body = await resp.Content.ReadAsStringAsync();
        throw ExceptionMapping.FromHttpStatus(resp.StatusCode, body);
    }

    // ── Health ──

    public async Task<HealthStatus> HealthAsync()
    {
        try
        {
            var resp = await _http.GetAsync("/health");
            if (!resp.IsSuccessStatusCode)
                return new HealthStatus(false, "unknown");
            var json = await resp.Content.ReadFromJsonAsync<HealthResponseDto>(JsonOpts);
            return HealthStatusFromDto(json);
        }
        catch
        {
            return new HealthStatus(false, "unknown");
        }
    }

    /// <summary>
    /// Convert a parsed <see cref="HealthResponseDto"/> into a typed
    /// <see cref="HealthStatus"/>. Diagnostic fields default to empty / 0
    /// when talking to a pre-0.4.0 daemon that omits them.
    /// </summary>
    internal static HealthStatus HealthStatusFromDto(HealthResponseDto? dto)
    {
        if (dto is null) return new HealthStatus(false, "unknown");
        return new HealthStatus(
            dto.Status == "ok",
            dto.Network ?? "unknown",
            dto.Version ?? "",
            dto.EvmNetwork ?? "",
            dto.UptimeSeconds ?? 0,
            dto.BuildCommit ?? "",
            dto.PaymentTokenAddress ?? "",
            dto.PaymentVaultAddress ?? "");
    }

    // ── Data ──

    public async Task<PutResult> DataPutPublicAsync(byte[] data, string? paymentMode = null)
    {
        object body = paymentMode != null
            ? new { data = Convert.ToBase64String(data), payment_mode = paymentMode }
            : new { data = Convert.ToBase64String(data) };
        var resp = await PostJsonAsync<DataPutPublicDto>("/v1/data/public", body);
        return new PutResult(resp.Cost, resp.Address);
    }

    public async Task<byte[]> DataGetPublicAsync(string address)
    {
        var resp = await GetJsonAsync<DataGetDto>($"/v1/data/public/{address}");
        return Convert.FromBase64String(resp.Data);
    }

    public async Task<PutResult> DataPutPrivateAsync(byte[] data, string? paymentMode = null)
    {
        object body = paymentMode != null
            ? new { data = Convert.ToBase64String(data), payment_mode = paymentMode }
            : new { data = Convert.ToBase64String(data) };
        var resp = await PostJsonAsync<DataPutPrivateDto>("/v1/data/private", body);
        return new PutResult(resp.Cost, resp.DataMap);
    }

    public async Task<byte[]> DataGetPrivateAsync(string dataMap)
    {
        var resp = await GetJsonAsync<DataGetDto>($"/v1/data/private?data_map={Uri.EscapeDataString(dataMap)}");
        return Convert.FromBase64String(resp.Data);
    }

    public async Task<UploadCostEstimate> DataCostAsync(byte[] data)
    {
        var resp = await PostJsonAsync<CostDto>("/v1/data/cost", new { data = Convert.ToBase64String(data) });
        return new UploadCostEstimate(resp.Cost, resp.FileSize, resp.ChunkCount, resp.EstimatedGasCostWei, resp.PaymentMode);
    }

    // ── Chunks ──

    public async Task<PutResult> ChunkPutAsync(byte[] data)
    {
        var resp = await PostJsonAsync<DataPutPublicDto>("/v1/chunks", new { data = Convert.ToBase64String(data) });
        return new PutResult(resp.Cost, resp.Address);
    }

    public async Task<byte[]> ChunkGetAsync(string address)
    {
        var resp = await GetJsonAsync<DataGetDto>($"/v1/chunks/{address}");
        return Convert.FromBase64String(resp.Data);
    }

    /// <summary>
    /// Prepares a single chunk for external-signer publish via
    /// <c>POST /v1/chunks/prepare</c>.
    ///
    /// The daemon quotes the close group for the supplied bytes and returns
    /// either <see cref="PrepareChunkResult.AlreadyStored"/> = <c>true</c> with
    /// <see cref="PrepareChunkResult.Address"/> set (no payment needed), or a
    /// wave-batch payment intent. Mirrors <see cref="ChunkPutAsync"/> but
    /// routes payment through an external signer instead of the daemon wallet.
    ///
    /// Requires antd &gt;= 0.7.0.
    /// </summary>
    public async Task<PrepareChunkResult> PrepareChunkUploadAsync(byte[] data)
    {
        var resp = await PostJsonAsync<PrepareChunkDto>("/v1/chunks/prepare",
            new { data = Convert.ToBase64String(data) });
        var payments = resp.Payments?
            .Select(p => new PaymentInfo(p.QuoteHash, p.RewardsAddress, p.Amount))
            .ToList() ?? new List<PaymentInfo>();
        return new PrepareChunkResult(
            resp.Address ?? "",
            resp.AlreadyStored,
            resp.UploadId ?? "",
            resp.PaymentType ?? "",
            payments,
            resp.TotalAmount ?? "",
            resp.PaymentVaultAddress ?? "",
            resp.PaymentTokenAddress ?? "",
            resp.RpcUrl ?? "");
    }

    /// <summary>
    /// Submits a prepared chunk to the network after the external signer has
    /// paid via <c>POST /v1/chunks/finalize</c>. Returns the hex address of
    /// the stored chunk (matches <see cref="PrepareChunkResult.Address"/>).
    ///
    /// Requires antd &gt;= 0.7.0.
    /// </summary>
    public async Task<string> FinalizeChunkUploadAsync(string uploadId, IDictionary<string, string> txHashes)
    {
        var resp = await PostJsonAsync<FinalizeChunkDto>("/v1/chunks/finalize",
            new { upload_id = uploadId, tx_hashes = txHashes });
        return resp.Address ?? "";
    }

    // ── Files ──

    public async Task<FileUploadResult> FileUploadPublicAsync(string path, string? paymentMode = null)
    {
        object body = paymentMode != null
            ? new { path, payment_mode = paymentMode }
            : (object)new { path };
        var resp = await PostJsonAsync<FileUploadPublicDto>("/v1/files/upload/public", body);
        return new FileUploadResult(resp.Address, resp.StorageCostAtto, resp.GasCostWei, resp.ChunksStored, resp.PaymentModeUsed);
    }

    public async Task FileDownloadPublicAsync(string address, string destPath)
    {
        await PostJsonNoResultAsync("/v1/files/download/public", new { address, dest_path = destPath });
    }

    public async Task<UploadCostEstimate> FileCostAsync(string path, bool isPublic = true)
    {
        var body = new { path, is_public = isPublic };
        var resp = await PostJsonAsync<CostDto>("/v1/files/cost", body);
        return new UploadCostEstimate(resp.Cost, resp.FileSize, resp.ChunkCount, resp.EstimatedGasCostWei, resp.PaymentMode);
    }

    // ── Wallet ──

    public async Task<WalletAddress> WalletAddressAsync()
    {
        var resp = await GetJsonAsync<WalletAddressDto>("/v1/wallet/address");
        return new WalletAddress(resp.Address);
    }

    public async Task<WalletBalance> WalletBalanceAsync()
    {
        var resp = await GetJsonAsync<WalletBalanceDto>("/v1/wallet/balance");
        return new WalletBalance(resp.Balance, resp.GasBalance);
    }

    /// <summary>
    /// Approves the wallet to spend tokens on payment contracts (one-time operation).
    /// </summary>
    public async Task<bool> WalletApproveAsync()
    {
        var resp = await PostJsonAsync<WalletApproveDto>("/v1/wallet/approve", new { });
        return resp.Approved;
    }

    // ── External Signer (Two-Phase Upload) ──

    /// <summary>
    /// Prepares a file upload for external signing.
    /// </summary>
    /// <param name="path">Path to the file to upload.</param>
    /// <param name="visibility">
    /// Pass <c>"public"</c> to bundle the DataMap chunk into the same
    /// external-signer payment batch — the resulting
    /// <see cref="FinalizeUploadResult.DataMapAddress"/> is the shareable
    /// retrieval handle. <c>"private"</c> or <c>null</c> preserves the
    /// pre-public daemon wire shape (private-only).
    /// </param>
    public async Task<PrepareUploadResult> PrepareUploadAsync(string path, string? visibility = null)
    {
        object body = visibility != null
            ? new { path, visibility }
            : (object)new { path };
        var resp = await PostJsonAsync<PrepareUploadDto>("/v1/upload/prepare", body);
        return MapPrepareUpload(resp);
    }

    /// <summary>
    /// Convenience wrapper: prepares a <em>public</em> file upload for external
    /// signing. Equivalent to <see cref="PrepareUploadAsync"/> with
    /// <c>visibility="public"</c>.
    ///
    /// Requires antd &gt;= 0.6.1.
    /// </summary>
    public Task<PrepareUploadResult> PrepareUploadPublicAsync(string path)
        => PrepareUploadAsync(path, visibility: "public");

    /// <summary>
    /// Prepares a data upload for external signing.
    /// Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
    /// </summary>
    /// <param name="data">Raw bytes to upload.</param>
    /// <param name="visibility">
    /// Pass <c>"public"</c> to request the public flow; note the daemon
    /// currently returns 501 for <c>visibility="public"</c> on the data path
    /// until upstream <c>data_prepare_upload_with_visibility</c> lands. Use
    /// <see cref="PrepareUploadPublicAsync"/> with a file path until then.
    /// </param>
    public async Task<PrepareUploadResult> PrepareDataUploadAsync(byte[] data, string? visibility = null)
    {
        object body = visibility != null
            ? new { data = Convert.ToBase64String(data), visibility }
            : (object)new { data = Convert.ToBase64String(data) };
        var resp = await PostJsonAsync<PrepareUploadDto>("/v1/data/prepare", body);
        return MapPrepareUpload(resp);
    }

    /// <summary>
    /// Finalizes an upload after an external signer has submitted payment transactions.
    /// </summary>
    public async Task<FinalizeUploadResult> FinalizeUploadAsync(string uploadId, Dictionary<string, string> txHashes)
    {
        var resp = await PostJsonAsync<FinalizeUploadDto>("/v1/upload/finalize", new { upload_id = uploadId, tx_hashes = txHashes });
        return new FinalizeUploadResult(
            resp.Address ?? "",
            resp.ChunksStored,
            resp.DataMap ?? "",
            resp.DataMapAddress ?? "");
    }

    /// <summary>
    /// Finalizes a merkle batch upload by selecting a winner pool.
    /// </summary>
    public async Task<FinalizeMerkleUploadResult> FinalizeMerkleUploadAsync(string uploadId, string winnerPoolHash)
    {
        var resp = await PostJsonAsync<FinalizeUploadDto>("/v1/upload/finalize",
            new { upload_id = uploadId, winner_pool_hash = winnerPoolHash });
        return new FinalizeMerkleUploadResult(
            resp.Address ?? "",
            resp.ChunksStored,
            resp.DataMap ?? "",
            resp.DataMapAddress ?? "");
    }

    private static PrepareUploadResult MapPrepareUpload(PrepareUploadDto resp)
    {
        var payments = resp.Payments?.Select(p => new PaymentInfo(p.QuoteHash, p.RewardsAddress, p.Amount)).ToList() ?? [];
        var poolCommitments = resp.PoolCommitments?.Select(pc =>
            new PoolCommitmentEntry(pc.PoolHash, pc.Candidates.Select(c => new CandidateNodeEntry(c.RewardsAddress, c.Amount)).ToList())
        ).ToList();
        return new PrepareUploadResult(
            resp.UploadId, payments, resp.TotalAmount, resp.PaymentVaultAddress,
            resp.PaymentTokenAddress, resp.RpcUrl,
            PaymentType: resp.PaymentType ?? "wave_batch",
            Depth: resp.Depth,
            PoolCommitments: poolCommitments,
            MerklePaymentTimestamp: resp.MerklePaymentTimestamp);
    }

    // ── Internal DTOs for JSON deserialization ──

    internal sealed record HealthResponseDto(
        [property: JsonPropertyName("status")] string Status,
        [property: JsonPropertyName("network")] string? Network,
        [property: JsonPropertyName("version")] string? Version = null,
        [property: JsonPropertyName("evm_network")] string? EvmNetwork = null,
        [property: JsonPropertyName("uptime_seconds")] ulong? UptimeSeconds = null,
        [property: JsonPropertyName("build_commit")] string? BuildCommit = null,
        [property: JsonPropertyName("payment_token_address")] string? PaymentTokenAddress = null,
        [property: JsonPropertyName("payment_vault_address")] string? PaymentVaultAddress = null);

    private sealed record DataPutPublicDto(
        [property: JsonPropertyName("cost")] string Cost,
        [property: JsonPropertyName("address")] string Address);

    private sealed record FileUploadPublicDto(
        [property: JsonPropertyName("address")] string Address,
        [property: JsonPropertyName("storage_cost_atto")] string StorageCostAtto,
        [property: JsonPropertyName("gas_cost_wei")] string GasCostWei,
        [property: JsonPropertyName("chunks_stored")] ulong ChunksStored,
        [property: JsonPropertyName("payment_mode_used")] string PaymentModeUsed);

    private sealed record DataPutPrivateDto(
        [property: JsonPropertyName("cost")] string Cost,
        [property: JsonPropertyName("data_map")] string DataMap);

    private sealed record DataGetDto(
        [property: JsonPropertyName("data")] string Data);

    private sealed record CostDto(
        [property: JsonPropertyName("cost")] string Cost,
        [property: JsonPropertyName("file_size")] ulong FileSize = 0,
        [property: JsonPropertyName("chunk_count")] uint ChunkCount = 0,
        [property: JsonPropertyName("estimated_gas_cost_wei")] string EstimatedGasCostWei = "",
        [property: JsonPropertyName("payment_mode")] string PaymentMode = "");

    private sealed record WalletAddressDto(
        [property: JsonPropertyName("address")] string Address);

    private sealed record WalletBalanceDto(
        [property: JsonPropertyName("balance")] string Balance,
        [property: JsonPropertyName("gas_balance")] string GasBalance);

    private sealed record WalletApproveDto(
        [property: JsonPropertyName("approved")] bool Approved);

    private sealed record PaymentInfoDto(
        [property: JsonPropertyName("quote_hash")] string QuoteHash,
        [property: JsonPropertyName("rewards_address")] string RewardsAddress,
        [property: JsonPropertyName("amount")] string Amount);

    private sealed record CandidateNodeEntryDto(
        [property: JsonPropertyName("rewards_address")] string RewardsAddress,
        [property: JsonPropertyName("amount")] string Amount);

    private sealed record PoolCommitmentEntryDto(
        [property: JsonPropertyName("pool_hash")] string PoolHash,
        [property: JsonPropertyName("candidates")] List<CandidateNodeEntryDto> Candidates);

    private sealed record PrepareUploadDto(
        [property: JsonPropertyName("upload_id")] string UploadId,
        [property: JsonPropertyName("payments")] List<PaymentInfoDto>? Payments,
        [property: JsonPropertyName("total_amount")] string TotalAmount,
        [property: JsonPropertyName("payment_vault_address")] string PaymentVaultAddress,
        [property: JsonPropertyName("payment_token_address")] string PaymentTokenAddress,
        [property: JsonPropertyName("rpc_url")] string RpcUrl,
        [property: JsonPropertyName("payment_type")] string? PaymentType = null,
        [property: JsonPropertyName("depth")] int? Depth = null,
        [property: JsonPropertyName("pool_commitments")] List<PoolCommitmentEntryDto>? PoolCommitments = null,
        [property: JsonPropertyName("merkle_payment_timestamp")] long? MerklePaymentTimestamp = null);

    private sealed record FinalizeUploadDto(
        [property: JsonPropertyName("address")] string? Address = null,
        [property: JsonPropertyName("chunks_stored")] long ChunksStored = 0,
        [property: JsonPropertyName("data_map")] string? DataMap = null,
        [property: JsonPropertyName("data_map_address")] string? DataMapAddress = null);

    private sealed record PrepareChunkDto(
        [property: JsonPropertyName("address")] string? Address = null,
        [property: JsonPropertyName("already_stored")] bool AlreadyStored = false,
        [property: JsonPropertyName("upload_id")] string? UploadId = null,
        [property: JsonPropertyName("payment_type")] string? PaymentType = null,
        [property: JsonPropertyName("payments")] List<PaymentInfoDto>? Payments = null,
        [property: JsonPropertyName("total_amount")] string? TotalAmount = null,
        [property: JsonPropertyName("payment_vault_address")] string? PaymentVaultAddress = null,
        [property: JsonPropertyName("payment_token_address")] string? PaymentTokenAddress = null,
        [property: JsonPropertyName("rpc_url")] string? RpcUrl = null);

    private sealed record FinalizeChunkDto(
        [property: JsonPropertyName("address")] string? Address = null);
}
