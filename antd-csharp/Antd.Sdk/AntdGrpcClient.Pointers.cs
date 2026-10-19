using Grpc.Core;
using Pb = Antd.V1;

namespace Antd.Sdk;

// Pointers over gRPC (PointerService): the same methods, models and
// exceptions as the REST client. The daemon tags the errors that share a gRPC
// status with older ones (POINTER_FINAL and POINTER_FORKED on
// FAILED_PRECONDITION, CONFLICT on ABORTED, CLOSE_GROUP_SHORTFALL on
// UNAVAILABLE) with an x-antd-error-code trailer, which
// ExceptionMapping.FromGrpcStatus reads from RpcException.Trailers. Every
// write is sent exactly once: nothing here retries.
public sealed partial class AntdGrpcClient
{
    /// <summary>Runs one PointerService call and maps its failure, trailers included.</summary>
    private static async Task<T> PointerCallAsync<T>(Func<AsyncUnaryCall<T>> call)
    {
        try { return await call(); }
        catch (RpcException ex) { throw Wrap(ex); }
    }

    public async Task<List<string>> PointerKeysAsync()
    {
        var resp = await PointerCallAsync(() => _pointer.ListKeysAsync(new Pb.ListPointerKeysRequest()));
        return resp.Keys.Select(k => k.Address).ToList();
    }

    public Task<PointerWriteResult> PointerCreateAsync(string owner, string target, PointerKind kind = PointerKind.Chunk)
        => PointerWriteAsync(owner, target, kind, update: false);

    public Task<PointerWriteResult> PointerUpdateAsync(string owner, string target, PointerKind kind = PointerKind.Chunk)
        => PointerWriteAsync(owner, target, kind, update: true);

    private async Task<PointerWriteResult> PointerWriteAsync(string owner, string target, PointerKind kind, bool update)
    {
        var req = new Pb.PointerWriteRequest { Owner = owner, Target = target, Kind = kind.ToWire() };
        var resp = await PointerCallAsync(() => update ? _pointer.UpdateAsync(req) : _pointer.CreateAsync(req));
        return new PointerWriteResult(resp.Address, resp.StateId, PointerWire.ParseCounter("counter", resp.Counter));
    }

    public async Task<PointerTransferResult> PointerTransferAsync(string owner, string recipient)
    {
        var resp = await PointerCallAsync(() => _pointer.TransferAsync(
            new Pb.PointerTransferRequest { Owner = owner, Recipient = recipient }));
        return new PointerTransferResult(
            resp.Address,
            resp.StateId,
            resp.Finality is null ? null : MapFinality(resp.Finality),
            PointerWire.NullIfEmpty(resp.FinalityError));
    }

    public async Task<PointerRecord> PointerGetAsync(string address)
    {
        var resp = await PointerCallAsync(() => _pointer.GetAsync(new Pb.GetPointerRequest { Address = address }));
        return new PointerRecord(
            resp.Address,
            resp.Owner,
            PointerWire.ParseCounter("counter", resp.Counter),
            resp.Kind,
            KindTag(resp.KindTag),
            resp.Target,
            resp.StateId,
            resp.IsFinal,
            PointerWire.NullIfEmpty(resp.TransferredTo));
    }

    public async Task<PointerTarget> PointerResolveAsync(string address)
    {
        var resp = await PointerCallAsync(() => _pointer.ResolveAsync(new Pb.ResolvePointerRequest { Address = address }));
        return new PointerTarget(resp.Kind, KindTag(resp.KindTag), resp.Target);
    }

    public async Task<PointerFinality> PointerFinalityAsync(string address)
    {
        var resp = await PointerCallAsync(() => _pointer.FinalityAsync(new Pb.PointerFinalityRequest { Address = address }));
        return MapFinality(resp);
    }

    public async Task<PointerController> PointerControllerAsync(string address)
    {
        var resp = await PointerCallAsync(() => _pointer.ControllerAsync(new Pb.PointerControllerRequest { Address = address }));
        return new PointerController(resp.Pointer, resp.Transfers.ToList(), resp.Frozen);
    }

    public async Task<PointerPrepareResult> PointerPrepareAsync(PointerPrepareRequest request)
    {
        // proto3 strings have no null: an unset field is the empty string.
        var isTransfer = request.Op == PointerOp.Transfer;
        var req = new Pb.PreparePointerRequest
        {
            Owner = request.Owner,
            Op = request.Op.ToWire(),
            Target = request.Target ?? "",
            Kind = isTransfer ? "" : request.Kind.ToWire(),
            Recipient = request.Recipient ?? "",
        };
        var resp = await PointerCallAsync(() => _pointer.PrepareAsync(req));
        return new PointerPrepareResult(
            resp.UploadId,
            resp.Op,
            resp.Address,
            resp.StateId,
            PointerWire.ParseCounter("counter", resp.Counter),
            resp.PaymentType,
            resp.Payments.Select(p => new PaymentInfo(p.QuoteHash, p.RewardsAddress, p.Amount)).ToList(),
            resp.TotalAmount,
            resp.PaymentVaultAddress,
            resp.PaymentTokenAddress,
            resp.RpcUrl);
    }

    public async Task<PointerFinalizeResult> PointerFinalizeAsync(string uploadId, IDictionary<string, string> txHashes)
    {
        var req = new Pb.FinalizePointerRequest { UploadId = uploadId };
        foreach (var kv in txHashes) req.TxHashes[kv.Key] = kv.Value;
        var resp = await PointerCallAsync(() => _pointer.FinalizeAsync(req));
        return new PointerFinalizeResult(
            resp.Address,
            resp.StateId,
            PointerWire.ParseCounter("counter", resp.Counter),
            resp.Finality is null ? null : MapFinality(resp.Finality));
    }

    /// <summary>
    /// The proto carries the target tag as a uint32; the daemon only sends
    /// u8 values. Anything wider is a protocol violation, not a tag to wrap.
    /// </summary>
    private static byte KindTag(uint tag) =>
        tag <= byte.MaxValue
            ? (byte)tag
            : throw new AntdException($"antd: pointer kind_tag {tag} is out of range");

    private static PointerFinalState MapFinalState(Pb.PointerFinalState s) =>
        new(s.StateId, s.Kind, KindTag(s.KindTag), s.Target, s.Holders, PointerWire.NullIfEmpty(s.TransferredTo));

    /// <summary>
    /// The proto finality shape, where an unset counter or transferred_to is
    /// the empty string and an unset state or majority an absent message.
    /// </summary>
    private static PointerFinality MapFinality(Pb.PointerFinality f) =>
        new(
            f.Address,
            f.Group,
            f.Answered,
            PointerFinalityStatusExtensions.FromWire(f.Status),
            f.Status,
            f.Counter.Length == 0 ? null : PointerWire.ParseCounter("finality counter", f.Counter),
            f.State is null ? null : MapFinalState(f.State),
            f.States.Select(MapFinalState).ToList(),
            f.Majority is null ? null : MapFinalState(f.Majority),
            PointerWire.NullIfEmpty(f.TransferredTo));
}
