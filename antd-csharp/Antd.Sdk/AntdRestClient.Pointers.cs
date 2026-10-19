using System.Text.Json.Serialization;

namespace Antd.Sdk;

// Pointers over REST (/v1/pointers). See IAntdClient for each method's
// contract. Every write pays and is sent exactly once: nothing here retries.
public sealed partial class AntdRestClient
{
    public async Task<List<string>> PointerKeysAsync()
    {
        var resp = await GetJsonAsync<PointerKeysDto>("/v1/pointers/keys");
        return resp.Keys?.Select(k => k.Address ?? "").ToList() ?? [];
    }

    public Task<PointerWriteResult> PointerCreateAsync(string owner, string target, PointerKind kind = PointerKind.Chunk)
        => PointerWriteAsync("/v1/pointers", owner, target, kind);

    public Task<PointerWriteResult> PointerUpdateAsync(string owner, string target, PointerKind kind = PointerKind.Chunk)
        => PointerWriteAsync("/v1/pointers/update", owner, target, kind);

    private async Task<PointerWriteResult> PointerWriteAsync(string path, string owner, string target, PointerKind kind)
    {
        var resp = await PostJsonAsync<PointerWriteDto>(path, new { owner, target, kind = kind.ToWire() });
        return new PointerWriteResult(
            resp.Address ?? "", resp.StateId ?? "", PointerWire.ParseCounter("counter", resp.Counter));
    }

    public async Task<PointerTransferResult> PointerTransferAsync(string owner, string recipient)
    {
        var resp = await PostJsonAsync<PointerTransferDto>("/v1/pointers/transfer", new { owner, recipient });
        return new PointerTransferResult(
            resp.Address ?? "",
            resp.StateId ?? "",
            resp.Finality is null ? null : MapFinality(resp.Finality),
            PointerWire.NullIfEmpty(resp.FinalityError));
    }

    public async Task<PointerRecord> PointerGetAsync(string address)
    {
        var resp = await GetJsonAsync<PointerRecordDto>($"/v1/pointers/{Uri.EscapeDataString(address)}");
        return new PointerRecord(
            resp.Address ?? "",
            resp.Owner ?? "",
            PointerWire.ParseCounter("counter", resp.Counter),
            resp.Kind ?? "",
            resp.KindTag,
            resp.Target ?? "",
            resp.StateId ?? "",
            resp.IsFinal,
            PointerWire.NullIfEmpty(resp.TransferredTo));
    }

    public async Task<PointerTarget> PointerResolveAsync(string address)
    {
        var resp = await GetJsonAsync<PointerResolvedDto>($"/v1/pointers/{Uri.EscapeDataString(address)}/resolve");
        return new PointerTarget(resp.Kind ?? "", resp.KindTag, resp.Target ?? "");
    }

    public async Task<PointerFinality> PointerFinalityAsync(string address)
    {
        var resp = await GetJsonAsync<PointerFinalityDto>($"/v1/pointers/{Uri.EscapeDataString(address)}/finality");
        return MapFinality(resp);
    }

    public async Task<PointerController> PointerControllerAsync(string address)
    {
        var resp = await GetJsonAsync<PointerControllerDto>($"/v1/pointers/{Uri.EscapeDataString(address)}/controller");
        return new PointerController(resp.Pointer ?? "", resp.Transfers ?? [], resp.Frozen);
    }

    public async Task<PointerPrepareResult> PointerPrepareAsync(PointerPrepareRequest request)
    {
        // target / kind belong to create and update, recipient to transfer;
        // null fields are left out of the body.
        var isTransfer = request.Op == PointerOp.Transfer;
        var body = new
        {
            owner = request.Owner,
            op = request.Op.ToWire(),
            target = request.Target,
            kind = isTransfer ? null : request.Kind.ToWire(),
            recipient = request.Recipient,
        };
        var resp = await PostJsonAsync<PointerPrepareDto>("/v1/pointers/prepare", body);
        return new PointerPrepareResult(
            resp.UploadId ?? "",
            resp.Op ?? "",
            resp.Address ?? "",
            resp.StateId ?? "",
            PointerWire.ParseCounter("counter", resp.Counter),
            resp.PaymentType ?? "",
            resp.Payments?.Select(p => new PaymentInfo(p.QuoteHash, p.RewardsAddress, p.Amount)).ToList() ?? [],
            resp.TotalAmount ?? "",
            resp.PaymentVaultAddress ?? "",
            resp.PaymentTokenAddress ?? "",
            resp.RpcUrl ?? "");
    }

    public async Task<PointerFinalizeResult> PointerFinalizeAsync(string uploadId, IDictionary<string, string> txHashes)
    {
        var resp = await PostJsonAsync<PointerFinalizeDto>("/v1/pointers/finalize",
            new { upload_id = uploadId, tx_hashes = txHashes });
        return new PointerFinalizeResult(
            resp.Address ?? "",
            resp.StateId ?? "",
            PointerWire.ParseCounter("counter", resp.Counter),
            resp.Finality is null ? null : MapFinality(resp.Finality));
    }

    private static PointerFinalState MapFinalState(PointerFinalStateDto s) =>
        new(s.StateId ?? "", s.Kind ?? "", s.KindTag, s.Target ?? "", s.Holders, PointerWire.NullIfEmpty(s.TransferredTo));

    /// <summary>
    /// The REST finality shape: an unset counter, state, majority or
    /// transferred_to is <c>null</c>; a counter, when set, must be a decimal
    /// <see cref="ulong"/>.
    /// </summary>
    private static PointerFinality MapFinality(PointerFinalityDto f) =>
        new(
            f.Address ?? "",
            f.Group,
            f.Answered,
            PointerFinalityStatusExtensions.FromWire(f.Status),
            f.Status ?? "",
            string.IsNullOrEmpty(f.Counter) ? null : PointerWire.ParseCounter("finality counter", f.Counter),
            f.State is null ? null : MapFinalState(f.State),
            f.States?.Select(MapFinalState).ToList() ?? [],
            f.Majority is null ? null : MapFinalState(f.Majority),
            PointerWire.NullIfEmpty(f.TransferredTo));

    // Counters are strings on the wire (a final state is u64::MAX); they are
    // parsed by PointerWire.ParseCounter, never read as JSON numbers.

    private sealed record PointerKeyDto(
        [property: JsonPropertyName("address")] string? Address);

    private sealed record PointerKeysDto(
        [property: JsonPropertyName("keys")] List<PointerKeyDto>? Keys);

    private sealed record PointerWriteDto(
        [property: JsonPropertyName("address")] string? Address,
        [property: JsonPropertyName("state_id")] string? StateId,
        [property: JsonPropertyName("counter")] string? Counter);

    private sealed record PointerTransferDto(
        [property: JsonPropertyName("address")] string? Address,
        [property: JsonPropertyName("state_id")] string? StateId,
        [property: JsonPropertyName("finality")] PointerFinalityDto? Finality = null,
        [property: JsonPropertyName("finality_error")] string? FinalityError = null);

    private sealed record PointerRecordDto(
        [property: JsonPropertyName("address")] string? Address,
        [property: JsonPropertyName("owner")] string? Owner,
        [property: JsonPropertyName("counter")] string? Counter,
        [property: JsonPropertyName("kind")] string? Kind,
        [property: JsonPropertyName("kind_tag")] byte KindTag,
        [property: JsonPropertyName("target")] string? Target,
        [property: JsonPropertyName("state_id")] string? StateId,
        [property: JsonPropertyName("is_final")] bool IsFinal,
        [property: JsonPropertyName("transferred_to")] string? TransferredTo = null);

    private sealed record PointerResolvedDto(
        [property: JsonPropertyName("kind")] string? Kind,
        [property: JsonPropertyName("kind_tag")] byte KindTag,
        [property: JsonPropertyName("target")] string? Target);

    private sealed record PointerFinalStateDto(
        [property: JsonPropertyName("state_id")] string? StateId,
        [property: JsonPropertyName("kind")] string? Kind,
        [property: JsonPropertyName("kind_tag")] byte KindTag,
        [property: JsonPropertyName("target")] string? Target,
        [property: JsonPropertyName("holders")] uint Holders,
        [property: JsonPropertyName("transferred_to")] string? TransferredTo = null);

    private sealed record PointerFinalityDto(
        [property: JsonPropertyName("address")] string? Address,
        [property: JsonPropertyName("group")] uint Group,
        [property: JsonPropertyName("answered")] uint Answered,
        [property: JsonPropertyName("status")] string? Status,
        [property: JsonPropertyName("counter")] string? Counter = null,
        [property: JsonPropertyName("state")] PointerFinalStateDto? State = null,
        [property: JsonPropertyName("states")] List<PointerFinalStateDto>? States = null,
        [property: JsonPropertyName("majority")] PointerFinalStateDto? Majority = null,
        [property: JsonPropertyName("transferred_to")] string? TransferredTo = null);

    private sealed record PointerControllerDto(
        [property: JsonPropertyName("pointer")] string? Pointer,
        [property: JsonPropertyName("transfers")] List<string>? Transfers,
        [property: JsonPropertyName("frozen")] bool Frozen);

    private sealed record PointerPrepareDto(
        [property: JsonPropertyName("upload_id")] string? UploadId,
        [property: JsonPropertyName("op")] string? Op,
        [property: JsonPropertyName("address")] string? Address,
        [property: JsonPropertyName("state_id")] string? StateId,
        [property: JsonPropertyName("counter")] string? Counter,
        [property: JsonPropertyName("payment_type")] string? PaymentType,
        [property: JsonPropertyName("payments")] List<PaymentInfoDto>? Payments,
        [property: JsonPropertyName("total_amount")] string? TotalAmount,
        [property: JsonPropertyName("payment_vault_address")] string? PaymentVaultAddress,
        [property: JsonPropertyName("payment_token_address")] string? PaymentTokenAddress,
        [property: JsonPropertyName("rpc_url")] string? RpcUrl);

    private sealed record PointerFinalizeDto(
        [property: JsonPropertyName("address")] string? Address,
        [property: JsonPropertyName("state_id")] string? StateId,
        [property: JsonPropertyName("counter")] string? Counter,
        [property: JsonPropertyName("finality")] PointerFinalityDto? Finality = null);
}
