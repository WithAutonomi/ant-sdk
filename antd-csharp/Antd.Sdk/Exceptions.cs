using System.Globalization;
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
/// <c>ABORTED</c> whose status detail starts with the daemon's fixed
/// <c>Partial upload:</c> prefix). The on-chain payment persists and the
/// stored chunks stay on the network. How to finish the upload depends on
/// <see cref="Retryable"/> and <see cref="RetentionKnown"/>:
/// <list type="bullet">
/// <item><description>
/// <see cref="Retryable"/> is <c>true</c>: the daemon kept the paid attempt
/// (payment proofs plus the unstored chunks) under the same <c>upload_id</c>.
/// Call the same finalize method again with the same arguments (the same
/// <c>upload_id</c> and payment artefacts) to store the remainder against the
/// same payment: no re-prepare, no second signature, no double payment.
/// Bound that loop: a persistent failure throws this exception on every
/// call, so cap the attempts and treat a <see cref="ChunksFailed"/> that
/// stops shrinking as stuck. The retained attempt expires with the daemon's
/// pending-upload TTL.
/// </description></item>
/// <item><description>
/// <see cref="RetentionKnown"/> is <c>true</c> and <see cref="Retryable"/> is
/// <c>false</c>: the daemon confirmed it kept nothing (for example a merkle
/// finalize that deliberately left sub-batches unpaid). Re-prepare the same
/// content; already-stored chunks are skipped, so the retry pays only for
/// the remainder.
/// </description></item>
/// <item><description>
/// <see cref="RetentionKnown"/> is <c>false</c>: retention is unknown. The
/// daemon may still hold the paid attempt, because it records the resume
/// handle before it returns the error. Stop automatic recovery, keep the
/// <c>upload_id</c> and the original payment artefacts, and reconcile before
/// re-preparing or paying again; never pay again on this signal alone.
/// Daemons before antd 0.14.0 never send <c>retryable</c>, so their REST
/// partial uploads read as unknown.
/// </description></item>
/// </list>
/// Extends <see cref="NetworkException"/> because a partial upload has
/// always arrived as a 502, so existing <c>catch (NetworkException)</c>
/// blocks keep matching; catch this type first to branch on the counts.
/// Over REST the counts come from the structured error body (a count that
/// is missing or not a JSON number reads as zero), and
/// <see cref="RetentionKnown"/> is <c>true</c> only when <c>retryable</c> is
/// a JSON boolean. Over gRPC they are parsed from the status detail
/// (<c>Partial upload: S/T chunks stored, F failed after retries: &lt;reason&gt; (&lt;hint&gt;)</c>,
/// where the closing hint starts <c>paid attempt retained</c> when the daemon
/// kept the attempt and <c>stored chunks persist; re-prepare the same
/// content</c> when it did not; daemons before antd 0.14.0 write only the
/// second): <see cref="RetentionKnown"/> is <c>true</c> only when the detail
/// starts with the counts, all three convert, and the detail ends with one
/// of those two hints; the hint then decides <see cref="Retryable"/>. A
/// detail whose counts do not match or do not convert (an overflow,
/// non-ASCII digits) leaves all three counts zero and both flags
/// <c>false</c>, even with a hint. Readable counts with a missing, truncated
/// or unrecognised closing hint, or text after it, keep the counts, but both
/// flags stay <c>false</c>: retention unknown, not "nothing retained".
/// Over gRPC a partial-upload <c>ABORTED</c> used to map to
/// <see cref="ForkException"/> and now maps to this exception (the daemon
/// emits <c>ABORTED</c> only for PARTIAL_UPLOAD); an <c>ABORTED</c> whose
/// detail does not start with the prefix (including one that quotes it
/// further in) is still a <see cref="ForkException"/>.
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
    /// the remainder against the same payment. Implies
    /// <see cref="RetentionKnown"/>. <c>false</c> alone does not mean nothing
    /// was retained: check <see cref="RetentionKnown"/> before re-preparing.
    /// </summary>
    public bool Retryable { get; }

    /// <summary>
    /// <c>true</c> when the error said whether the daemon retained the paid
    /// attempt, so <see cref="Retryable"/> is the daemon's answer rather than
    /// a fallback. REST: the 502 body carried <c>retryable</c> as a JSON
    /// boolean. gRPC: the status detail started with the
    /// <c>Partial upload:</c> counts, all three parsed, and the detail ended
    /// with one of the daemon's two retention hints,
    /// <c>(paid attempt retained...)</c> or
    /// <c>(stored chunks persist; re-prepare the same content...)</c>; that
    /// hint then decides <see cref="Retryable"/>. <c>false</c> means
    /// retention is unknown (a daemon before antd 0.14.0 answering over REST,
    /// or an error the SDK could not fully read, such as a gRPC detail whose
    /// closing hint is missing or cut short):
    /// the daemon may still hold the paid attempt, so keep the
    /// <c>upload_id</c> and payment artefacts and reconcile before
    /// re-preparing or paying again.
    /// </summary>
    public bool RetentionKnown { get; }

    /// <summary>
    /// Creates a partial-upload exception whose retention is known only when
    /// <paramref name="retryable"/> is <c>true</c>; a <c>false</c>
    /// <paramref name="retryable"/> reads as unknown retention, the
    /// conservative reading. Kept for source compatibility: the overload
    /// taking <c>retentionKnown</c> states it explicitly.
    /// </summary>
    public PartialUploadException(
        string message,
        ulong chunksStored,
        ulong chunksFailed,
        ulong totalChunks,
        bool retryable,
        int statusCode = 502)
        : this(message, chunksStored, chunksFailed, totalChunks, retryable, retentionKnown: retryable, statusCode)
    {
    }

    /// <summary>
    /// Creates a partial-upload exception. <paramref name="retryable"/>
    /// implies <paramref name="retentionKnown"/>: a <c>true</c>
    /// <paramref name="retryable"/> sets <see cref="RetentionKnown"/>
    /// whatever <paramref name="retentionKnown"/> says.
    /// </summary>
    public PartialUploadException(
        string message,
        ulong chunksStored,
        ulong chunksFailed,
        ulong totalChunks,
        bool retryable,
        bool retentionKnown,
        int statusCode = 502)
        : base(message, statusCode)
    {
        ChunksStored = chunksStored;
        ChunksFailed = chunksFailed;
        TotalChunks = totalChunks;
        Retryable = retryable;
        RetentionKnown = retentionKnown || retryable;
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
    /// Opening words of the hint that closes a PARTIAL_UPLOAD message when
    /// the daemon kept the paid attempt for a same-<c>upload_id</c> retry
    /// (<c>partial_upload_hint</c> in antd/src/error.rs).
    /// </summary>
    private const string PartialUploadRetainedHint = "paid attempt retained";

    /// <summary>
    /// Opening words of the hint that closes a PARTIAL_UPLOAD message when
    /// the daemon did not keep the paid attempt. Daemons before antd 0.14.0
    /// close every PARTIAL_UPLOAD message with this hint, in this wording.
    /// </summary>
    private const string PartialUploadNotRetainedHint = "stored chunks persist; re-prepare the same content";

    /// <summary>
    /// Fixed text every PARTIAL_UPLOAD message from the daemon opens with.
    /// Over gRPC it is the only marker that distinguishes a partial upload
    /// from any other <c>ABORTED</c> status, so the mapping gates on the
    /// status detail starting with it (anchored, as in antd-rust).
    /// </summary>
    private const string PartialUploadPrefix = "Partial upload:";

    /// <summary>
    /// Count layout of the daemon's PARTIAL_UPLOAD message, anchored at its
    /// start: <c>Partial upload: &lt;stored&gt;/&lt;total&gt; chunks stored, &lt;failed&gt; failed</c>.
    /// ASCII digits only: .NET's <c>\d</c> also matches other Unicode decimal
    /// digits, which the daemon never sends.
    /// </summary>
    [GeneratedRegex(@"\APartial upload: ([0-9]+)/([0-9]+) chunks stored, ([0-9]+) failed")]
    private static partial Regex PartialUploadCounts();

    /// <summary>
    /// The retention hint that closes the message: <c>(&lt;hint&gt;...)</c>
    /// at the very end, where the hint opens with one of the two phrases
    /// above and the rest holds no parenthesis. Anchored with <c>\z</c>, not
    /// <c>$</c>, which would also match before a trailing newline. A hint
    /// quoted inside the failure reason, a truncated or unclosed tail, or
    /// text after the hint does not match. Neither phrase holds a regex
    /// metacharacter, so both are spliced in unescaped.
    /// </summary>
    [GeneratedRegex(@"\((" + PartialUploadRetainedHint + "|" + PartialUploadNotRetainedHint + @")[^()]*\)\z")]
    private static partial Regex PartialUploadRetentionTail();

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
    /// <c>total_chunks</c>, <c>retryable</c>). Retention is known only when
    /// <c>retryable</c> is a JSON boolean; absent (daemons before 0.14.0),
    /// <c>null</c> or any other kind reads as unknown and not retryable. A
    /// body that is not
    /// a readable JSON object, or whose <c>code</c> is not the string
    /// <c>"PARTIAL_UPLOAD"</c>, is left to the status-based mapping. A count
    /// or flag of the wrong JSON kind reads as zero / <c>false</c>, and an
    /// <c>error</c> that is not a decodable string falls back to the raw
    /// body. The body is network input, so this never throws.
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
            if (ReadString(root, "code") != PartialUploadCode)
                return false;

            var message = ReadString(root, "error") ?? body!;
            var retentionKnown = root.TryGetProperty("retryable", out var r)
                && r.ValueKind is JsonValueKind.True or JsonValueKind.False;
            partial = new PartialUploadException(
                message,
                ReadCount(root, "chunks_stored"),
                ReadCount(root, "chunks_failed"),
                ReadCount(root, "total_chunks"),
                retryable: retentionKnown && r.ValueKind == JsonValueKind.True,
                retentionKnown,
                statusCode);
            return true;
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or ArgumentException)
        {
            // JsonException: malformed JSON. InvalidOperationException: a
            // property name whose escape is not valid UTF-16 (a lone
            // surrogate), which System.Text.Json throws on when it has to
            // unescape the name to compare it. ArgumentException: input text
            // that is not valid UTF-16. None is a body this mapper can read,
            // so the status-based mapping applies.
            return false;
        }
    }

    /// <summary>
    /// The value at <paramref name="name"/> when it is a JSON string that
    /// decodes; <c>null</c> when it is absent, another JSON kind, or an escape
    /// that is not valid UTF-16 (a lone surrogate), on which
    /// <see cref="JsonElement.GetString"/> would throw.
    /// </summary>
    private static string? ReadString(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var el) || el.ValueKind != JsonValueKind.String)
            return null;
        try
        {
            return el.GetString();
        }
        catch (InvalidOperationException)
        {
            return null;
        }
    }

    private static ulong ReadCount(JsonElement root, string name) =>
        root.TryGetProperty(name, out var el) && el.ValueKind == JsonValueKind.Number && el.TryGetUInt64(out var v)
            ? v
            : 0UL;

    /// <summary>
    /// Recovers the chunk counts, the retention verdict and the retryable
    /// hint from a PARTIAL_UPLOAD message. Used for gRPC, where the status
    /// carries no structured detail; REST callers get the body fields
    /// instead. <c>RetentionKnown</c> is <c>true</c> only when the message
    /// opens with the count layout, all three counts convert to
    /// <see cref="ulong"/>, and the message ends with one of the daemon's
    /// two retention hints; <c>Retryable</c> is then <c>true</c> only for
    /// the retained hint. On a layout miss or any failed conversion (an
    /// overflow) all three counts are zero and both flags are <c>false</c>
    /// whatever the hint says: a retry loop that cannot watch the failed
    /// count shrink cannot tell progress from a stuck upload, and an
    /// unreadable message says nothing reliable about what the daemon kept.
    /// Readable counts with a missing, truncated or unrecognised closing
    /// hint, or text after it, keep the counts but leave both flags
    /// <c>false</c>: the daemon's answer on retention was not read, so
    /// retention is unknown, never "nothing retained". Whether the message
    /// is a partial upload at all is decided by
    /// <see cref="IsPartialUploadMessage"/>.
    /// </summary>
    internal static (ulong Stored, ulong Failed, ulong Total, bool Retryable, bool RetentionKnown) ParsePartialUploadMessage(string? message)
    {
        var msg = message ?? "";
        var m = PartialUploadCounts().Match(msg);
        if (!m.Success
            || !TryParseCount(m.Groups[1].Value, out var stored)
            || !TryParseCount(m.Groups[2].Value, out var total)
            || !TryParseCount(m.Groups[3].Value, out var failed))
        {
            return (0, 0, 0, false, false);
        }
        var tail = PartialUploadRetentionTail().Match(msg);
        if (!tail.Success)
            return (stored, failed, total, false, false);
        return (stored, failed, total, tail.Groups[1].Value == PartialUploadRetainedHint, true);
    }

    /// <summary>
    /// Converts one captured run of ASCII digits; <c>false</c> when it does
    /// not fit in a <see cref="ulong"/>.
    /// </summary>
    private static bool TryParseCount(string digits, out ulong value) =>
        ulong.TryParse(digits, NumberStyles.None, CultureInfo.InvariantCulture, out value);

    public static AntdException FromGrpcStatus(RpcException ex)
    {
        // The raw status detail, not RpcException.Message: Grpc.Net formats
        // the latter as Status(StatusCode="...", Detail="..."), which would
        // defeat the anchored PARTIAL_UPLOAD match below.
        var detail = ex.Status.Detail;
        return ex.StatusCode switch
        {
            Grpc.Core.StatusCode.NotFound => new NotFoundException(detail),
            Grpc.Core.StatusCode.AlreadyExists => new AlreadyExistsException(detail),
            // ABORTED carries the daemon's PARTIAL_UPLOAD (some chunks stored,
            // some still unstored after retries) when the status detail
            // starts with the fixed "Partial upload:" prefix. The counts and
            // the closing retention hint ride the detail text over gRPC (no
            // structured detail yet), so parse them best-effort to match the
            // REST client's typed exception: RetentionKnown needs the counts
            // and one of the daemon's two hints at the very end of the
            // detail, and only "paid attempt retained" sets Retryable. Such
            // an ABORTED used to map to ForkException; the daemon emits
            // ABORTED only for PARTIAL_UPLOAD. Any other ABORTED, including
            // one that quotes the prefix further into its detail, keeps the
            // pre-existing version-conflict mapping.
            Grpc.Core.StatusCode.Aborted => AbortedFromGrpc(detail),
            Grpc.Core.StatusCode.InvalidArgument => new BadRequestException(detail),
            Grpc.Core.StatusCode.FailedPrecondition => new PaymentException(detail),
            Grpc.Core.StatusCode.Unavailable => new NetworkException(detail),
            Grpc.Core.StatusCode.ResourceExhausted => new TooLargeException(detail),
            Grpc.Core.StatusCode.Internal => new InternalException(detail),
            _ => new AntdException(detail, (int)ex.StatusCode),
        };
    }

    private static AntdException AbortedFromGrpc(string detail)
    {
        if (!IsPartialUploadMessage(detail))
            return new ForkException(detail);
        var (stored, failed, total, retryable, retentionKnown) = ParsePartialUploadMessage(detail);
        return new PartialUploadException(detail, stored, failed, total, retryable, retentionKnown);
    }

    /// <summary>
    /// <c>true</c> when the gRPC status detail starts with the daemon's fixed
    /// PARTIAL_UPLOAD prefix. Anchored rather than a containment check, so an
    /// unrelated <c>ABORTED</c> that merely quotes the phrase further into its
    /// detail is not misreported as a partial upload. The daemon
    /// sends its PARTIAL_UPLOAD message as the detail unwrapped, so a genuine
    /// partial upload always has the prefix at offset zero. Pass the raw
    /// <c>Status.Detail</c>, not <c>RpcException.Message</c>.
    /// </summary>
    internal static bool IsPartialUploadMessage(string? message) =>
        message?.StartsWith(PartialUploadPrefix, StringComparison.Ordinal) == true;
}
