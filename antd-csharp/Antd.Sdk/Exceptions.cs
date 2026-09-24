using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using Grpc.Core;

namespace Antd.Sdk;

public class AntdException : Exception
{
    public int StatusCode { get; }

    public AntdException(string message, int statusCode = 0)
        : base(message) => StatusCode = statusCode;
}

public class NotFoundException : AntdException
{
    public NotFoundException(string message, int statusCode = 404)
        : base(message, statusCode) { }
}

public class AlreadyExistsException : AntdException
{
    public AlreadyExistsException(string message, int statusCode = 409)
        : base(message, statusCode) { }
}

public class ForkException : AntdException
{
    public ForkException(string message, int statusCode = 409)
        : base(message, statusCode) { }
}

public class BadRequestException : AntdException
{
    public BadRequestException(string message, int statusCode = 400)
        : base(message, statusCode) { }
}

public class PaymentException : AntdException
{
    public PaymentException(string message, int statusCode = 402)
        : base(message, statusCode) { }
}

public class NetworkException : AntdException
{
    public NetworkException(string message, int statusCode = 502)
        : base(message, statusCode) { }
}

/// <summary>
/// A finalize stored some chunks while others remained unstored after the
/// daemon's retries (HTTP 502 with <c>code: "PARTIAL_UPLOAD"</c>; gRPC
/// <c>ABORTED</c>). The on-chain payment persists and the stored chunks stay
/// on the network. How to finish the upload depends on <see cref="Retryable"/>:
/// <list type="bullet">
/// <item><description>
/// <see cref="Retryable"/> is <c>true</c>: the daemon kept the paid attempt
/// (payment proofs plus the unstored chunks) under the same <c>upload_id</c>.
/// Call the same finalize method again with the same arguments to store the
/// remainder against the same payment: no re-prepare, no second signature,
/// no double payment. Bound that loop: a persistent failure throws this
/// exception on every call, so cap the attempts and treat a
/// <see cref="ChunksFailed"/> that stops shrinking as stuck. The retained
/// attempt expires with the daemon's pending-upload TTL. (antd 0.14.0 and
/// later; older daemons never send the flag, so it reads <c>false</c> and the
/// re-prepare path applies.)
/// </description></item>
/// <item><description>
/// <see cref="Retryable"/> is <c>false</c>: nothing was retained (a merkle
/// finalize with deliberately unpaid batches, or an older daemon).
/// Re-preparing the same content skips already-stored chunks, so a retry
/// pays only for the missing remainder.
/// </description></item>
/// </list>
/// Extends <see cref="NetworkException"/> because a partial upload has
/// always arrived as a 502, so existing <c>catch (NetworkException)</c>
/// blocks keep matching; catch this type first to branch on the counts.
/// Over REST the counts and flag come from the structured error body. Over
/// gRPC they are parsed best-effort from the status message
/// (<c>Partial upload: S/T chunks stored, F failed ...</c>, with a
/// <c>paid attempt retained</c> hint when retryable); an unrecognised
/// message leaves the counts zero and <see cref="Retryable"/> false.
/// See docs/external-signer-flow.md, section 6.
/// </summary>
public class PartialUploadException : NetworkException
{
    /// <summary>Chunks the daemon confirmed stored before it gave up.</summary>
    public ulong ChunksStored { get; }

    /// <summary>Chunks still unstored after the daemon's own retries.</summary>
    public ulong ChunksFailed { get; }

    /// <summary>Chunks the finalize was asked to store in total.</summary>
    public ulong TotalChunks { get; }

    /// <summary>
    /// <c>true</c> when the daemon retained the paid attempt under the same
    /// <c>upload_id</c>, so the same finalize call can be repeated to store
    /// the remainder against the same payment. Defaults to <c>false</c> when
    /// the daemon did not send the flag (antd before 0.14.0).
    /// </summary>
    public bool Retryable { get; }

    public PartialUploadException(
        string message,
        ulong chunksStored,
        ulong chunksFailed,
        ulong totalChunks,
        bool retryable,
        int statusCode = 502)
        : base(message, statusCode)
    {
        ChunksStored = chunksStored;
        ChunksFailed = chunksFailed;
        TotalChunks = totalChunks;
        Retryable = retryable;
    }
}

public class ServiceUnavailableException : AntdException
{
    public ServiceUnavailableException(string message, int statusCode = 503)
        : base(message, statusCode) { }
}

public class TooLargeException : AntdException
{
    public TooLargeException(string message, int statusCode = 413)
        : base(message, statusCode) { }
}

public class InternalException : AntdException
{
    public InternalException(string message, int statusCode = 500)
        : base(message, statusCode) { }
}

internal static partial class ExceptionMapping
{
    /// <summary>Machine-readable <c>code</c> the daemon sets on a partial upload.</summary>
    private const string PartialUploadCode = "PARTIAL_UPLOAD";

    /// <summary>
    /// Message tail the daemon appends when it kept the paid attempt for a
    /// same-<c>upload_id</c> retry.
    /// </summary>
    private const string PartialUploadRetainedHint = "paid attempt retained";

    /// <summary>
    /// Fixed prefix of the daemon's PARTIAL_UPLOAD message:
    /// <c>Partial upload: &lt;stored&gt;/&lt;total&gt; chunks stored, &lt;failed&gt; failed</c>.
    /// </summary>
    [GeneratedRegex(@"Partial upload: (\d+)/(\d+) chunks stored, (\d+) failed")]
    private static partial Regex PartialUploadCounts();

    public static AntdException FromHttpStatus(HttpStatusCode status, string body)
    {
        var code = (int)status;
        // Prefer the machine-readable `code` over the bare status where they
        // diverge: PARTIAL_UPLOAD arrives as a 502 that would otherwise read
        // as a generic NetworkException. Every other code keeps the
        // status-based mapping below.
        if (TryParsePartialUploadBody(body, code, out var partial))
            return partial!;
        return code switch
        {
            400 => new BadRequestException(body, code),
            402 => new PaymentException(body, code),
            404 => new NotFoundException(body, code),
            409 => new ForkException(body, code),
            413 => new TooLargeException(body, code),
            500 => new InternalException(body, code),
            502 => new NetworkException(body, code),
            503 => new ServiceUnavailableException(body, code),
            _ => new AntdException(body, code),
        };
    }

    /// <summary>
    /// Recognises the daemon's structured PARTIAL_UPLOAD body
    /// (<c>error</c>, <c>code</c>, <c>chunks_stored</c>, <c>chunks_failed</c>,
    /// <c>total_chunks</c>, <c>retryable</c>). <c>retryable</c> is absent on
    /// daemons before 0.14.0 and then reads <c>false</c>. A non-JSON body, or
    /// any other <c>code</c>, is left to the status-based mapping.
    /// </summary>
    private static bool TryParsePartialUploadBody(string body, int statusCode, out PartialUploadException? partial)
    {
        partial = null;
        var trimmed = body?.TrimStart() ?? "";
        if (trimmed.Length == 0 || trimmed[0] != '{')
            return false;
        try
        {
            using var doc = JsonDocument.Parse(trimmed);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return false;
            if (!root.TryGetProperty("code", out var codeEl) || codeEl.ValueKind != JsonValueKind.String
                || codeEl.GetString() != PartialUploadCode)
                return false;

            var message = root.TryGetProperty("error", out var errEl) && errEl.ValueKind == JsonValueKind.String
                ? errEl.GetString() ?? body!
                : body!;
            var retryable = root.TryGetProperty("retryable", out var r) && r.ValueKind == JsonValueKind.True;
            partial = new PartialUploadException(
                message,
                ReadCount(root, "chunks_stored"),
                ReadCount(root, "chunks_failed"),
                ReadCount(root, "total_chunks"),
                retryable,
                statusCode);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static ulong ReadCount(JsonElement root, string name) =>
        root.TryGetProperty(name, out var el) && el.ValueKind == JsonValueKind.Number && el.TryGetUInt64(out var v)
            ? v
            : 0UL;

    /// <summary>
    /// Recovers the chunk counts and the retryable hint from a PARTIAL_UPLOAD
    /// message. Used for gRPC, where the status carries no structured detail;
    /// REST callers get the body fields instead. An unrecognised message
    /// yields zero counts and <c>Retryable == false</c>.
    /// </summary>
    internal static (ulong Stored, ulong Failed, ulong Total, bool Retryable) ParsePartialUploadMessage(string? message)
    {
        var msg = message ?? "";
        ulong stored = 0, failed = 0, total = 0;
        var m = PartialUploadCounts().Match(msg);
        if (m.Success)
        {
            ulong.TryParse(m.Groups[1].Value, out stored);
            ulong.TryParse(m.Groups[2].Value, out total);
            ulong.TryParse(m.Groups[3].Value, out failed);
        }
        var retryable = msg.Contains(PartialUploadRetainedHint, StringComparison.Ordinal);
        return (stored, failed, total, retryable);
    }

    public static AntdException FromGrpcStatus(RpcException ex)
    {
        var detail = ex.Status.Detail;
        return ex.StatusCode switch
        {
            Grpc.Core.StatusCode.NotFound => new NotFoundException(detail),
            Grpc.Core.StatusCode.AlreadyExists => new AlreadyExistsException(detail),
            // ABORTED is the daemon's PARTIAL_UPLOAD: some chunks stored, some
            // still unstored after retries. The counts and the "paid attempt
            // retained" hint ride the message text over gRPC (no structured
            // detail yet), so parse them best-effort to match the REST
            // client's typed exception.
            Grpc.Core.StatusCode.Aborted => PartialUploadFromGrpc(detail),
            Grpc.Core.StatusCode.InvalidArgument => new BadRequestException(detail),
            Grpc.Core.StatusCode.FailedPrecondition => new PaymentException(detail),
            Grpc.Core.StatusCode.Unavailable => new NetworkException(detail),
            Grpc.Core.StatusCode.ResourceExhausted => new TooLargeException(detail),
            Grpc.Core.StatusCode.Internal => new InternalException(detail),
            _ => new AntdException(detail, (int)ex.StatusCode),
        };
    }

    private static PartialUploadException PartialUploadFromGrpc(string detail)
    {
        var (stored, failed, total, retryable) = ParsePartialUploadMessage(detail);
        return new PartialUploadException(detail, stored, failed, total, retryable);
    }
}
