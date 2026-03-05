using System.Net;
using System.Net.Http.Json;
using System.Text;
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

    public AntdRestClient(string baseUrl = "http://localhost:8080", TimeSpan? timeout = null)
    {
        _baseUrl = baseUrl.TrimEnd('/');
        _http = new HttpClient { BaseAddress = new Uri(_baseUrl), Timeout = timeout ?? TimeSpan.FromSeconds(300) };
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

    private async Task<T> PutJsonAsync<T>(string path, object body)
    {
        var content = JsonContent.Create(body, options: JsonOpts);
        var resp = await _http.PutAsync(path, content);
        await EnsureSuccessAsync(resp);
        return (await resp.Content.ReadFromJsonAsync<T>(JsonOpts))!;
    }

    private async Task PutJsonNoResultAsync(string path, object body)
    {
        var content = JsonContent.Create(body, options: JsonOpts);
        var resp = await _http.PutAsync(path, content);
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

    public async Task<PutResult> DataPutPublicAsync(byte[] data)
    {
        var resp = await PostJsonAsync<DataPutPublicDto>("/v1/data/public", new { data = Convert.ToBase64String(data) });
        return new PutResult(resp.Cost, resp.Address);
    }

    public async Task<byte[]> DataGetPublicAsync(string address)
    {
        var resp = await GetJsonAsync<DataGetDto>($"/v1/data/public/{address}");
        return Convert.FromBase64String(resp.Data);
    }

    public async Task<PutResult> DataPutPrivateAsync(byte[] data)
    {
        var resp = await PostJsonAsync<DataPutPrivateDto>("/v1/data/private", new { data = Convert.ToBase64String(data) });
        return new PutResult(resp.Cost, resp.DataMap);
    }

    public async Task<byte[]> DataGetPrivateAsync(string dataMap)
    {
        var resp = await GetJsonAsync<DataGetDto>($"/v1/data/private?data_map={dataMap}");
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

    // ── Pointers ──

    public async Task<PutResult> PointerCreateAsync(string ownerSecretKey, PointerTarget target)
    {
        var body = new { owner_secret_key = ownerSecretKey, target = new { kind = target.Kind, address = target.Address } };
        var resp = await PostJsonAsync<DataPutPublicDto>("/v1/pointers", body);
        return new PutResult(resp.Cost, resp.Address);
    }

    public async Task<Pointer> PointerGetAsync(string address)
    {
        var resp = await GetJsonAsync<PointerDto>($"/v1/pointers/{address}");
        return new Pointer(resp.Address, resp.Owner, resp.Counter, new PointerTarget(resp.Target.Kind, resp.Target.Address));
    }

    public Task<bool> PointerExistsAsync(string address) => HeadExistsAsync($"/v1/pointers/{address}");

    public async Task PointerUpdateAsync(string ownerSecretKey, PointerTarget target)
    {
        var body = new { owner_secret_key = ownerSecretKey, target = new { kind = target.Kind, address = target.Address } };
        await PutJsonNoResultAsync($"/v1/pointers/{ownerSecretKey}", body);
    }

    public async Task<string> PointerCostAsync(string publicKey)
    {
        var resp = await PostJsonAsync<CostDto>("/v1/pointers/cost", new { public_key = publicKey });
        return resp.Cost;
    }

    // ── Scratchpads ──

    public async Task<PutResult> ScratchpadCreateAsync(string ownerSecretKey, ulong contentType, byte[] data)
    {
        var body = new { owner_secret_key = ownerSecretKey, content_type = contentType, data = Convert.ToBase64String(data) };
        var resp = await PostJsonAsync<DataPutPublicDto>("/v1/scratchpads", body);
        return new PutResult(resp.Cost, resp.Address);
    }

    public async Task<ScratchpadRecord> ScratchpadGetAsync(string address)
    {
        var resp = await GetJsonAsync<ScratchpadDto>($"/v1/scratchpads/{address}");
        return new ScratchpadRecord(resp.Address, resp.DataEncoding, Convert.FromBase64String(resp.Data), resp.Counter);
    }

    public Task<bool> ScratchpadExistsAsync(string address) => HeadExistsAsync($"/v1/scratchpads/{address}");

    public async Task ScratchpadUpdateAsync(string ownerSecretKey, ulong contentType, byte[] data)
    {
        var body = new { owner_secret_key = ownerSecretKey, content_type = contentType, data = Convert.ToBase64String(data) };
        await PutJsonNoResultAsync($"/v1/scratchpads/{ownerSecretKey}", body);
    }

    public async Task<string> ScratchpadCostAsync(string publicKey)
    {
        var resp = await PostJsonAsync<CostDto>("/v1/scratchpads/cost", new { public_key = publicKey });
        return resp.Cost;
    }

    // ── Graph ──

    public async Task<PutResult> GraphEntryPutAsync(string ownerSecretKey, List<string> parents, string content, List<GraphDescendant> descendants)
    {
        var body = new
        {
            owner_secret_key = ownerSecretKey,
            parents,
            content,
            descendants = descendants.Select(d => new { public_key = d.PublicKey, content = d.Content }).ToList(),
        };
        var resp = await PostJsonAsync<DataPutPublicDto>("/v1/graph", body);
        return new PutResult(resp.Cost, resp.Address);
    }

    public async Task<GraphEntry> GraphEntryGetAsync(string address)
    {
        var resp = await GetJsonAsync<GraphEntryDto>($"/v1/graph/{address}");
        var descendants = resp.Descendants?.Select(d => new GraphDescendant(d.PublicKey, d.Content)).ToList() ?? [];
        return new GraphEntry(resp.Owner, resp.Parents ?? [], resp.Content, descendants);
    }

    public Task<bool> GraphEntryExistsAsync(string address) => HeadExistsAsync($"/v1/graph/{address}");

    public async Task<string> GraphEntryCostAsync(string publicKey)
    {
        var resp = await PostJsonAsync<CostDto>("/v1/graph/cost", new { public_key = publicKey });
        return resp.Cost;
    }

    // ── Registers ──

    public async Task<PutResult> RegisterCreateAsync(string ownerSecretKey, string initialValue)
    {
        var body = new { owner_secret_key = ownerSecretKey, initial_value = initialValue };
        var resp = await PostJsonAsync<DataPutPublicDto>("/v1/registers", body);
        return new PutResult(resp.Cost, resp.Address);
    }

    public async Task<Register> RegisterGetAsync(string address)
    {
        var resp = await GetJsonAsync<RegisterDto>($"/v1/registers/{address}");
        return new Register(resp.Value);
    }

    public async Task<PutResult> RegisterUpdateAsync(string ownerSecretKey, string newValue)
    {
        var body = new { owner_secret_key = ownerSecretKey, new_value = newValue };
        var resp = await PutJsonAsync<RegisterUpdateDto>($"/v1/registers/{ownerSecretKey}", body);
        return new PutResult(resp.Cost, "");
    }

    public async Task<string> RegisterCostAsync(string publicKey)
    {
        var resp = await PostJsonAsync<CostDto>("/v1/registers/cost", new { public_key = publicKey });
        return resp.Cost;
    }

    // ── Vaults ──

    public async Task<Vault> VaultGetAsync(string secretKey)
    {
        var resp = await GetJsonAsync<VaultDto>($"/v1/vaults?secret_key={secretKey}");
        return new Vault(Convert.FromBase64String(resp.Data), resp.ContentType);
    }

    public async Task<string> VaultPutAsync(string secretKey, byte[] data, ulong contentType)
    {
        var body = new { secret_key = secretKey, data = Convert.ToBase64String(data), content_type = contentType };
        var resp = await PostJsonAsync<CostDto>("/v1/vaults", body);
        return resp.Cost;
    }

    public async Task<string> VaultCostAsync(string secretKey, ulong maxSize)
    {
        var body = new { secret_key = secretKey, max_size = maxSize };
        var resp = await PostJsonAsync<CostDto>("/v1/vaults/cost", body);
        return resp.Cost;
    }

    // ── Files ──

    public async Task<PutResult> FileUploadPublicAsync(string path)
    {
        var resp = await PostJsonAsync<DataPutPublicDto>("/v1/files/upload/public", new { path });
        return new PutResult(resp.Cost, resp.Address);
    }

    public async Task FileDownloadPublicAsync(string address, string destPath)
    {
        await PostJsonNoResultAsync("/v1/files/download/public", new { address, dest_path = destPath });
    }

    public async Task<PutResult> DirUploadPublicAsync(string path)
    {
        var resp = await PostJsonAsync<DataPutPublicDto>("/v1/dirs/upload/public", new { path });
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

    private sealed record PointerTargetDto(
        [property: JsonPropertyName("kind")] string Kind,
        [property: JsonPropertyName("address")] string Address);

    private sealed record PointerDto(
        [property: JsonPropertyName("address")] string Address,
        [property: JsonPropertyName("owner")] string Owner,
        [property: JsonPropertyName("counter")] ulong Counter,
        [property: JsonPropertyName("target")] PointerTargetDto Target);

    private sealed record ScratchpadDto(
        [property: JsonPropertyName("address")] string Address,
        [property: JsonPropertyName("data_encoding")] ulong DataEncoding,
        [property: JsonPropertyName("data")] string Data,
        [property: JsonPropertyName("counter")] ulong Counter);

    private sealed record GraphDescendantDto(
        [property: JsonPropertyName("public_key")] string PublicKey,
        [property: JsonPropertyName("content")] string Content);

    private sealed record GraphEntryDto(
        [property: JsonPropertyName("owner")] string Owner,
        [property: JsonPropertyName("parents")] List<string>? Parents,
        [property: JsonPropertyName("content")] string Content,
        [property: JsonPropertyName("descendants")] List<GraphDescendantDto>? Descendants);

    private sealed record RegisterDto(
        [property: JsonPropertyName("value")] string Value);

    private sealed record RegisterUpdateDto(
        [property: JsonPropertyName("cost")] string Cost);

    private sealed record VaultDto(
        [property: JsonPropertyName("data")] string Data,
        [property: JsonPropertyName("content_type")] ulong ContentType);

    private sealed record ArchiveEntryDto(
        [property: JsonPropertyName("path")] string Path,
        [property: JsonPropertyName("address")] string Address,
        [property: JsonPropertyName("created")] ulong Created,
        [property: JsonPropertyName("modified")] ulong Modified,
        [property: JsonPropertyName("size")] ulong Size);

    private sealed record ArchiveDto(
        [property: JsonPropertyName("entries")] List<ArchiveEntryDto>? Entries);
}
