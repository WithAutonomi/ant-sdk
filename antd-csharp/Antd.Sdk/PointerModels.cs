using System.Globalization;

namespace Antd.Sdk;

// Pointers (ADR-0016 in ant-node), with ownership transfer (ADR-0018).
//
// A pointer is a small, owner-signed, mutable reference. Its address is
// derived from the owner's key and never changes; what it points at (a chunk,
// such as a public file's data map, or another pointer) can be changed by the
// owner. antd signs with owner keys it loaded at startup (--pointer-keys), so
// a write names the pointer by its address (owner), never by a key.
//
// Every write pays, and every attempt pays again: do not retry a create,
// update, transfer or finalize automatically. Reads are free to retry.

/// <summary>What a pointer's target is.</summary>
public enum PointerKind
{
    /// <summary>An immutable chunk, such as a public file's data map. The default.</summary>
    Chunk,

    /// <summary>
    /// Another pointer: a forwarding the owner can still change. Use a
    /// transfer to hand a pointer over for good.
    /// </summary>
    Pointer,
}

public static class PointerKindExtensions
{
    /// <summary>Serialize a <see cref="PointerKind"/> to the wire string the daemon expects.</summary>
    public static string ToWire(this PointerKind kind) => kind switch
    {
        PointerKind.Pointer => "pointer",
        _ => "chunk",
    };

    /// <summary>
    /// The kind a raw target tag names, or <c>null</c> for a tag this SDK does
    /// not know (<c>0</c> chunk, <c>1</c> pointer).
    /// </summary>
    public static PointerKind? FromTag(byte tag) => tag switch
    {
        0 => PointerKind.Chunk,
        1 => PointerKind.Pointer,
        _ => null,
    };
}

/// <summary>The write a <c>PointerPrepareAsync</c> signs for an external signer to pay.</summary>
public enum PointerOp
{
    /// <summary>Create the pointer. Refused if it already exists.</summary>
    Create,

    /// <summary>Point the pointer at a new target, creating it if it does not exist.</summary>
    Update,

    /// <summary>
    /// Hand the pointer over for good to the recipient's pointer, which must
    /// already exist. Irreversible once stored.
    /// </summary>
    Transfer,
}

public static class PointerOpExtensions
{
    /// <summary>Serialize a <see cref="PointerOp"/> to the wire string the daemon expects.</summary>
    public static string ToWire(this PointerOp op) => op switch
    {
        PointerOp.Update => "update",
        PointerOp.Transfer => "transfer",
        _ => "create",
    };
}

/// <summary>
/// Where a pointer stands with respect to finality, as its whole close group
/// reports it. <see cref="Unknown"/> is a status this SDK does not know (a
/// newer daemon); <see cref="PointerFinality.RawStatus"/> carries the wire
/// value either way.
/// </summary>
public enum PointerFinalityStatus
{
    /// <summary>A status this SDK does not know; see <see cref="PointerFinality.RawStatus"/>.</summary>
    Unknown = 0,

    /// <summary>
    /// No peer that answered holds a final state: the owner can still move the
    /// pointer. Rules a final state out only when every peer answered.
    /// </summary>
    Open,

    /// <summary>
    /// One final state, not yet held by a majority: a transfer still
    /// spreading, or a write that fell short.
    /// </summary>
    Settling,

    /// <summary>
    /// One final state held by a majority, but not every peer answered, so a
    /// rival could still be unseen. Ask again.
    /// </summary>
    Unconfirmed,

    /// <summary>
    /// One final state held by a majority, every peer answered, no rival. The
    /// only status a recipient should rely on.
    /// </summary>
    Final,

    /// <summary>The owner signed two or more different final states.</summary>
    Forked,
}

public static class PointerFinalityStatusExtensions
{
    /// <summary>
    /// Parse the daemon's wire string; anything this SDK does not know is
    /// <see cref="PointerFinalityStatus.Unknown"/>.
    /// </summary>
    public static PointerFinalityStatus FromWire(string? status) => status switch
    {
        "open" => PointerFinalityStatus.Open,
        "settling" => PointerFinalityStatus.Settling,
        "unconfirmed" => PointerFinalityStatus.Unconfirmed,
        "final" => PointerFinalityStatus.Final,
        "forked" => PointerFinalityStatus.Forked,
        _ => PointerFinalityStatus.Unknown,
    };
}

/// <summary>The state a pointer write stored.</summary>
/// <param name="Address">The pointer's address (bare hex).</param>
/// <param name="StateId">The stored state's id (hex).</param>
/// <param name="Counter">The state's counter. A final state (a transfer) sits at <see cref="ulong.MaxValue"/>.</param>
public sealed record PointerWriteResult(string Address, string StateId, ulong Counter);

/// <summary>A pointer's current state, as the network serves it.</summary>
/// <param name="Address">The pointer's address (bare hex).</param>
/// <param name="Owner">
/// The owner's ML-DSA-65 public key (hex, 1,952 bytes). The address is derived
/// from it, so it is the proof of who owns the pointer.
/// </param>
/// <param name="Counter">The state's counter; <see cref="ulong.MaxValue"/> once final.</param>
/// <param name="Kind">
/// <c>"chunk"</c>, <c>"pointer"</c>, or <c>"unknown"</c> for a kind the daemon
/// does not know; <paramref name="KindTag"/> carries the raw value either way.
/// </param>
/// <param name="KindTag">The raw target tag (<c>0</c> chunk, <c>1</c> pointer).</param>
/// <param name="Target">The address the pointer points at.</param>
/// <param name="StateId">The served state's id (hex).</param>
/// <param name="IsFinal">The state is at the final counter: nothing can replace it.</param>
/// <param name="TransferredTo">
/// The pointer this one was handed over to, when its final state is a
/// transfer; <c>null</c> otherwise.
/// </param>
public sealed record PointerRecord(
    string Address,
    string Owner,
    ulong Counter,
    string Kind,
    byte KindTag,
    string Target,
    string StateId,
    bool IsFinal,
    string? TransferredTo)
{
    /// <summary>The target's kind, or <c>null</c> when this SDK does not know its tag.</summary>
    public PointerKind? TargetKind => PointerKindExtensions.FromTag(KindTag);
}

/// <summary>Where a chain of pointers ends (<c>PointerResolveAsync</c>).</summary>
/// <param name="Kind"><c>"chunk"</c>, or <c>"unknown"</c> for a target kind the daemon does not know.</param>
/// <param name="KindTag">The raw target tag.</param>
/// <param name="Target">The address the chain ends at.</param>
public sealed record PointerTarget(string Kind, byte KindTag, string Target)
{
    /// <summary>The target's kind, or <c>null</c> when this SDK does not know its tag.</summary>
    public PointerKind? TargetKind => PointerKindExtensions.FromTag(KindTag);
}

/// <summary>One final state, as a finality check reports it.</summary>
/// <param name="StateId">The state's id (hex).</param>
/// <param name="Kind"><c>"chunk"</c>, <c>"pointer"</c> or <c>"unknown"</c>.</param>
/// <param name="KindTag">The raw target tag.</param>
/// <param name="Target">The address the state points at.</param>
/// <param name="Holders">How many peers of the close group hold it.</param>
/// <param name="TransferredTo">The pointer the state hands over to, when it is a transfer; <c>null</c> otherwise.</param>
public sealed record PointerFinalState(
    string StateId,
    string Kind,
    byte KindTag,
    string Target,
    uint Holders,
    string? TransferredTo);

/// <summary>The answer to a pointer finality check (<c>PointerFinalityAsync</c>).</summary>
/// <param name="Address">The pointer's address (bare hex).</param>
/// <param name="Group">Peers in the close group.</param>
/// <param name="Answered">Peers that answered.</param>
/// <param name="Status">The parsed status; <see cref="PointerFinalityStatus.Unknown"/> for one this SDK does not know.</param>
/// <param name="RawStatus">The daemon's status string, as sent.</param>
/// <param name="Counter"><see cref="PointerFinalityStatus.Open"/> only: the counter a read would return, if any state is corroborated.</param>
/// <param name="State"><c>Settling</c>, <c>Unconfirmed</c> and <c>Final</c>: the one final state seen.</param>
/// <param name="States"><c>Forked</c> only: every final state seen, most-held first. Empty otherwise.</param>
/// <param name="Majority"><c>Forked</c> only: the state a majority holds, which reads return.</param>
/// <param name="TransferredTo">The pointer this one was handed over to, once that is beyond dispute (status <c>Final</c>).</param>
public sealed record PointerFinality(
    string Address,
    uint Group,
    uint Answered,
    PointerFinalityStatus Status,
    string RawStatus,
    ulong? Counter,
    PointerFinalState? State,
    List<PointerFinalState> States,
    PointerFinalState? Majority,
    string? TransferredTo)
{
    /// <summary>
    /// One final state, held by a majority, with every peer answering and no
    /// rival seen. Check this before relying on a transfer.
    /// </summary>
    public bool IsFinal => Status == PointerFinalityStatus.Final;
}

/// <summary>What a transfer stored, and where the close group says it stands.</summary>
/// <param name="Address">The transferred pointer's address (bare hex).</param>
/// <param name="StateId">The final state's id (hex).</param>
/// <param name="Finality">
/// The close group's view once the write landed. <c>null</c> when that check
/// failed (see <paramref name="FinalityError"/>), which does not undo the
/// transfer: it is stored and final. Ask again with <c>PointerFinalityAsync</c>.
/// </param>
/// <param name="FinalityError">Why the finality check failed, when <paramref name="Finality"/> is <c>null</c>.</param>
public sealed record PointerTransferResult(
    string Address,
    string StateId,
    PointerFinality? Finality,
    string? FinalityError);

/// <summary>Whose pointer decides what an address resolves to, after every transfer.</summary>
/// <param name="Pointer">The pointer whose owner now decides.</param>
/// <param name="Transfers">Every pointer the address was handed over to, in order.</param>
/// <param name="Frozen"><paramref name="Pointer"/> is final without being handed over: nobody can move it.</param>
public sealed record PointerController(string Pointer, List<string> Transfers, bool Frozen);

/// <summary>
/// The write <c>PointerPrepareAsync</c> asks the daemon to sign and quote. Use
/// <see cref="Create"/>, <see cref="Update"/> or <see cref="Transfer"/> to
/// build one.
/// </summary>
/// <param name="Owner">Address of the pointer to write; the daemon must hold its key.</param>
/// <param name="Op">The write to sign.</param>
/// <param name="Target">Create / update: the address to point at.</param>
/// <param name="Kind">Create / update: what <paramref name="Target"/> is.</param>
/// <param name="Recipient">Transfer: the recipient's pointer, which must already exist.</param>
public sealed record PointerPrepareRequest(
    string Owner,
    PointerOp Op,
    string? Target = null,
    PointerKind Kind = PointerKind.Chunk,
    string? Recipient = null)
{
    /// <summary>
    /// Ask for the full signed quotes in <see cref="PointerPrepareResult.SignedQuotes"/>,
    /// for offline verification. Off by default; sent only when true.
    /// </summary>
    public bool IncludeSignedQuotes { get; init; }

    /// <summary>Create the pointer at <paramref name="owner"/>, pointing at <paramref name="target"/>.</summary>
    public static PointerPrepareRequest Create(string owner, string target, PointerKind kind = PointerKind.Chunk, bool includeSignedQuotes = false) =>
        new(owner, PointerOp.Create, target, kind) { IncludeSignedQuotes = includeSignedQuotes };

    /// <summary>Point the pointer at <paramref name="owner"/> at <paramref name="target"/>.</summary>
    public static PointerPrepareRequest Update(string owner, string target, PointerKind kind = PointerKind.Chunk, bool includeSignedQuotes = false) =>
        new(owner, PointerOp.Update, target, kind) { IncludeSignedQuotes = includeSignedQuotes };

    /// <summary>Hand the pointer at <paramref name="owner"/> over to the pointer at <paramref name="recipient"/>.</summary>
    public static PointerPrepareRequest Transfer(string owner, string recipient, bool includeSignedQuotes = false) =>
        new(owner, PointerOp.Transfer, Recipient: recipient) { IncludeSignedQuotes = includeSignedQuotes };
}

/// <summary>
/// One <c>payments</c> quote in full signed form, returned when a prepare asks
/// for signed quotes. Both byte payloads are base64 on both transports and
/// opaque: only antd parses them.
/// </summary>
/// <param name="QuoteHash">Quote hash (hex with 0x prefix); matches the <see cref="PaymentInfo"/> entry.</param>
/// <param name="Quote">base64 of the msgpack-serialized signed PaymentQuote.</param>
/// <param name="CommitmentSidecar">base64 of the msgpack-serialized StorageCommitment the quote pins; null for baseline quotes.</param>
public sealed record SignedQuoteEntry(string QuoteHash, string Quote, string? CommitmentSidecar = null);

/// <summary>
/// A pointer write signed by the daemon and quoted for an external signer.
/// Pay <see cref="Payments"/> with <c>payForQuotes()</c>, then call
/// <c>PointerFinalizeAsync</c>. While it awaits payment, other writes to the
/// pointer throw <see cref="ConflictException"/> until it is finalized or
/// expires (the daemon's one-hour pending TTL).
/// </summary>
/// <param name="UploadId">The session id to pass to <c>PointerFinalizeAsync</c>.</param>
/// <param name="Op"><c>"create"</c>, <c>"update"</c> or <c>"transfer"</c>.</param>
/// <param name="Address">The pointer's address (bare hex).</param>
/// <param name="StateId">The signed state's id (hex).</param>
/// <param name="Counter">The prepared state's counter; <see cref="ulong.MaxValue"/> for a transfer.</param>
/// <param name="PaymentType">Always <c>"wave_batch"</c>: a pointer state is paid with one quote.</param>
/// <param name="Payments">The quotes to pay with <c>payForQuotes()</c>.</param>
/// <param name="TotalAmount">Total to pay, in atto tokens (decimal string).</param>
/// <param name="PaymentVaultAddress">The payment vault contract.</param>
/// <param name="PaymentTokenAddress">The payment token contract.</param>
/// <param name="RpcUrl">The EVM RPC endpoint the daemon uses.</param>
public sealed record PointerPrepareResult(
    string UploadId,
    string Op,
    string Address,
    string StateId,
    ulong Counter,
    string PaymentType,
    List<PaymentInfo> Payments,
    string TotalAmount,
    string PaymentVaultAddress,
    string PaymentTokenAddress,
    string RpcUrl)
{
    /// <summary>
    /// Populated when the prepare set <see cref="PointerPrepareRequest.IncludeSignedQuotes"/>
    /// and payment is required; otherwise empty.
    /// </summary>
    public List<SignedQuoteEntry> SignedQuotes { get; init; } = [];
}

/// <summary>The state a pointer finalize stored.</summary>
/// <param name="Address">The pointer's address (bare hex).</param>
/// <param name="StateId">The stored state's id (hex).</param>
/// <param name="Counter">The stored state's counter; <see cref="ulong.MaxValue"/> for a transfer.</param>
/// <param name="Finality">Transfers only: where the close group says the transfer stands.</param>
public sealed record PointerFinalizeResult(
    string Address,
    string StateId,
    ulong Counter,
    PointerFinality? Finality);

internal static class PointerWire
{
    /// <summary>
    /// Parse a pointer counter. The daemon sends counters as decimal strings
    /// in both transports, because a final state sits at
    /// <see cref="ulong.MaxValue"/>, past what a JSON number keeps exactly in
    /// several languages. Only ASCII digits are accepted (no sign, no
    /// whitespace); anything else, or a value past <see cref="ulong.MaxValue"/>,
    /// throws rather than reading as zero.
    /// </summary>
    internal static ulong ParseCounter(string field, string? value)
    {
        if (!ulong.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var counter))
            throw new AntdException($"antd: pointer {field} \"{value}\" is not a decimal counter");
        return counter;
    }

    /// <summary>
    /// An unset value: REST sends <c>null</c>, gRPC the empty string. Both read
    /// as <c>null</c>.
    /// </summary>
    internal static string? NullIfEmpty(string? value) => string.IsNullOrEmpty(value) ? null : value;
}
