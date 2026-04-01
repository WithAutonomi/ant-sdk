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
            return new HealthStatus(json?.Status == "ok", json?.Network ?? "unknown");
        }
        catch
        {
            return new HealthStatus(false, "unknown");
        }
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

    public async Task<string> DataCostAsync(byte[] data)
    {
        var resp = await PostJsonAsync<CostDto>("/v1/data/cost", new { data = Convert.ToBase64String(data) });
        return resp.Cost;
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

    // ── Files ──

    public async Task<PutResult> FileUploadPublicAsync(string path, string? paymentMode = null)
    {
        object body = paymentMode != null
            ? new { path, payment_mode = paymentMode }
            : (object)new { path };
        var resp = await PostJsonAsync<DataPutPublicDto>("/v1/files/upload/public", body);
        return new PutResult(resp.Cost, resp.Address);
    }

    public async Task FileDownloadPublicAsync(string address, string destPath)
    {
        await PostJsonNoResultAsync("/v1/files/download/public", new { address, dest_path = destPath });
    }

    public async Task<PutResult> DirUploadPublicAsync(string path, string? paymentMode = null)
    {
        object body = paymentMode != null
            ? new { path, payment_mode = paymentMode }
            : (object)new { path };
        var resp = await PostJsonAsync<DataPutPublicDto>("/v1/dirs/upload/public", body);
        return new PutResult(resp.Cost, resp.Address);
    }

    public async Task DirDownloadPublicAsync(string address, string destPath)
    {
        await PostJsonNoResultAsync("/v1/dirs/download/public", new { address, dest_path = destPath });
    }

    public async Task<Archive> ArchiveGetPublicAsync(string address)
    {
        var resp = await GetJsonAsync<ArchiveDto>($"/v1/archives/public/{address}");
        var entries = resp.Entries?.Select(e => new ArchiveEntry(e.Path, e.Address, e.Created, e.Modified, e.Size)).ToList() ?? [];
        return new Archive(entries);
    }

    public async Task<PutResult> ArchivePutPublicAsync(Archive archive)
    {
        var body = new
        {
            entries = archive.Entries.Select(e => new
            {
                path = e.Path,
                address = e.Address,
                created = e.Created,
                modified = e.Modified,
                size = e.Size,
            }).ToList(),
        };
        var resp = await PostJsonAsync<DataPutPublicDto>("/v1/archives/public", body);
        return new PutResult(resp.Cost, resp.Address);
    }

    public async Task<string> FileCostAsync(string path, bool isPublic = true, bool includeArchive = false)
    {
        var body = new { path, is_public = isPublic, include_archive = includeArchive };
        var resp = await PostJsonAsync<CostDto>("/v1/cost/file", body);
        return resp.Cost;
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
    public async Task<PrepareUploadResult> PrepareUploadAsync(string path)
    {
        var resp = await PostJsonAsync<PrepareUploadDto>("/v1/upload/prepare", new { path });
        var payments = resp.Payments?.Select(p => new PaymentInfo(p.QuoteHash, p.RewardsAddress, p.Amount)).ToList() ?? [];
        return new PrepareUploadResult(resp.UploadId, payments, resp.TotalAmount, resp.DataPaymentsAddress, resp.PaymentTokenAddress, resp.RpcUrl);
    }

    /// <summary>
    /// Prepares a data upload for external signing.
    /// Takes raw bytes, base64-encodes them, and POSTs to /v1/data/prepare.
    /// </summary>
    public async Task<PrepareUploadResult> PrepareDataUploadAsync(byte[] data)
    {
        var resp = await PostJsonAsync<PrepareUploadDto>("/v1/data/prepare", new { data = Convert.ToBase64String(data) });
        var payments = resp.Payments?.Select(p => new PaymentInfo(p.QuoteHash, p.RewardsAddress, p.Amount)).ToList() ?? [];
        return new PrepareUploadResult(resp.UploadId, payments, resp.TotalAmount, resp.DataPaymentsAddress, resp.PaymentTokenAddress, resp.RpcUrl);
    }

    /// <summary>
    /// Finalizes an upload after an external signer has submitted payment transactions.
    /// </summary>
    public async Task<FinalizeUploadResult> FinalizeUploadAsync(string uploadId, Dictionary<string, string> txHashes)
    {
        var resp = await PostJsonAsync<FinalizeUploadDto>("/v1/upload/finalize", new { upload_id = uploadId, tx_hashes = txHashes });
        return new FinalizeUploadResult(resp.Address, resp.ChunksStored);
    }

    // ── Internal DTOs for JSON deserialization ──

    private sealed record HealthResponseDto(
        [property: JsonPropertyName("status")] string Status,
        [property: JsonPropertyName("network")] string? Network);

    private sealed record DataPutPublicDto(
        [property: JsonPropertyName("cost")] string Cost,
        [property: JsonPropertyName("address")] string Address);

    private sealed record DataPutPrivateDto(
        [property: JsonPropertyName("cost")] string Cost,
        [property: JsonPropertyName("data_map")] string DataMap);

    private sealed record DataGetDto(
        [property: JsonPropertyName("data")] string Data);

    private sealed record CostDto(
        [property: JsonPropertyName("cost")] string Cost);

    private sealed record ArchiveEntryDto(
        [property: JsonPropertyName("path")] string Path,
        [property: JsonPropertyName("address")] string Address,
        [property: JsonPropertyName("created")] ulong Created,
        [property: JsonPropertyName("modified")] ulong Modified,
        [property: JsonPropertyName("size")] ulong Size);

    private sealed record ArchiveDto(
        [property: JsonPropertyName("entries")] List<ArchiveEntryDto>? Entries);

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

    private sealed record PrepareUploadDto(
        [property: JsonPropertyName("upload_id")] string UploadId,
        [property: JsonPropertyName("payments")] List<PaymentInfoDto>? Payments,
        [property: JsonPropertyName("total_amount")] string TotalAmount,
        [property: JsonPropertyName("data_payments_address")] string DataPaymentsAddress,
        [property: JsonPropertyName("payment_token_address")] string PaymentTokenAddress,
        [property: JsonPropertyName("rpc_url")] string RpcUrl);

    private sealed record FinalizeUploadDto(
        [property: JsonPropertyName("address")] string Address,
        [property: JsonPropertyName("chunks_stored")] long ChunksStored);
}
