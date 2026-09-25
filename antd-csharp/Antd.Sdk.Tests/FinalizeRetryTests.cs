using Antd.Examples;
using Antd.Sdk;
using Xunit;

namespace Antd.Sdk.Tests;

/// <summary>
/// Direct tests for the external-signer example's bounded finalize retry
/// (Examples/FinalizeRetry.cs, compiled into this assembly).
/// </summary>
public sealed class FinalizeRetryTests
{
    private const string UploadId = "up_retry";

    private static readonly Dictionary<string, string> TxHashes = new()
    {
        ["0xq1"] = "0xtx1",
        ["0xq2"] = "0xtx2",
    };

    private static PartialUploadException Partial(ulong failed, bool retryable, bool retentionKnown) =>
        new($"Partial upload: {10 - failed}/10 chunks stored, {failed} failed after retries: quorum",
            10 - failed, failed, 10, retryable, retentionKnown);

    private static PartialUploadException Retained(ulong failed) => Partial(failed, retryable: true, retentionKnown: true);

    /// <summary>
    /// A stand-in finalize: records the arguments of every call and replays a
    /// scripted outcome per call (an exception to throw, or a result).
    /// </summary>
    private sealed class ScriptedFinalize
    {
        private readonly Queue<object> _outcomes;

        public ScriptedFinalize(params object[] outcomes) => _outcomes = new Queue<object>(outcomes);

        public List<(string UploadId, Dictionary<string, string> TxHashes)> Calls { get; } = new();

        public List<int> Backoffs { get; } = new();

        public Task<string> FinalizeAsync(string uploadId, Dictionary<string, string> txHashes)
        {
            // Snapshot the map so a later mutation could not hide a change.
            Calls.Add((uploadId, new Dictionary<string, string>(txHashes)));
            return _outcomes.Dequeue() switch
            {
                Exception e => Task.FromException<string>(e),
                var result => Task.FromResult((string)result),
            };
        }

        public Task<string> Run(int maxAttempts = FinalizeRetry.DefaultMaxAttempts, CancellationToken ct = default) =>
            FinalizeRetry.FinalizeWithRetryAsync(
                UploadId,
                () => FinalizeAsync(UploadId, TxHashes),
                maxAttempts,
                backoff: (attempt, _) => { Backoffs.Add(attempt); return Task.CompletedTask; },
                log: TextWriter.Null,
                cancellationToken: ct);
    }

    [Fact]
    public async Task Retryable_ShrinkingFailures_RetriesWithUnchangedArgumentsUntilComplete()
    {
        var script = new ScriptedFinalize(Retained(6), Retained(2), "0xdatamap");

        Assert.Equal("0xdatamap", await script.Run());

        Assert.Equal(3, script.Calls.Count);
        // Every attempt is the same finalize: same upload_id, same payment
        // artefacts. Nothing is re-prepared or paid again in between.
        Assert.All(script.Calls, call =>
        {
            Assert.Equal(UploadId, call.UploadId);
            Assert.Equal(TxHashes, call.TxHashes);
        });
        Assert.Equal(new[] { 1, 2 }, script.Backoffs);
    }

    [Fact]
    public async Task Retryable_Exhausted_RethrowsTheOriginalPartialUploadException()
    {
        var last = Retained(3);
        var script = new ScriptedFinalize(Retained(5), Retained(4), last);

        var ex = await Assert.ThrowsAsync<PartialUploadException>(() => script.Run(maxAttempts: 3));

        // The typed exception itself, not a wrapper: catch (AntdException)
        // and catch (NetworkException) still match and the counts survive.
        Assert.Same(last, ex);
        Assert.IsAssignableFrom<AntdException>(ex);
        Assert.True(ex.Retryable);
        Assert.Equal(3, script.Calls.Count);
        Assert.Equal(new[] { 1, 2 }, script.Backoffs);
    }

    [Theory]
    [InlineData(4UL, 4UL)] // no progress
    [InlineData(4UL, 5UL)] // got worse
    public async Task Retryable_StalledProgress_StopsAndRethrows(ulong firstFailed, ulong secondFailed)
    {
        var second = Retained(secondFailed);
        var script = new ScriptedFinalize(Retained(firstFailed), second, "never reached");

        var ex = await Assert.ThrowsAsync<PartialUploadException>(() => script.Run());

        Assert.Same(second, ex);
        Assert.Equal(2, script.Calls.Count);
        Assert.Equal(new[] { 1 }, script.Backoffs);
    }

    [Fact]
    public async Task RetentionKnownNotRetained_StopsAfterOneCallAndRethrows()
    {
        var notRetained = Partial(3, retryable: false, retentionKnown: true);
        var script = new ScriptedFinalize(notRetained, "never reached");

        var ex = await Assert.ThrowsAsync<PartialUploadException>(() => script.Run());

        Assert.Same(notRetained, ex);
        Assert.Single(script.Calls);
        Assert.Empty(script.Backoffs);
    }

    [Fact]
    public async Task RetentionUnknown_StopsWithoutRetryingAndRethrows()
    {
        // Unknown retention: the daemon may still hold the paid attempt, so
        // the helper must neither loop nor move on to a re-prepare; it hands
        // the typed exception back after the single call.
        var unknown = Partial(3, retryable: false, retentionKnown: false);
        var script = new ScriptedFinalize(unknown, "never reached");

        var ex = await Assert.ThrowsAsync<PartialUploadException>(() => script.Run());

        Assert.Same(unknown, ex);
        Assert.False(ex.RetentionKnown);
        Assert.Single(script.Calls);
        Assert.Empty(script.Backoffs);
    }

    [Fact]
    public async Task OtherException_PropagatesUntouched()
    {
        var down = new NetworkException("daemon unreachable");
        var script = new ScriptedFinalize(down, "never reached");

        var ex = await Assert.ThrowsAsync<NetworkException>(() => script.Run());

        Assert.Same(down, ex);
        Assert.Single(script.Calls);
    }

    [Fact]
    public async Task Cancellation_DuringBackoff_StopsBeforeTheNextAttempt()
    {
        using var cts = new CancellationTokenSource();
        var script = new ScriptedFinalize(Retained(5), "never reached");

        // The default backoff with the token cancelled while the first
        // attempt is in flight: no second finalize runs, and the exact
        // TaskCanceledException shows the wait itself honoured the token
        // (the loop's own check before the next attempt would throw a plain
        // OperationCanceledException, and only after the full delay).
        var run = FinalizeRetry.FinalizeWithRetryAsync(
            UploadId,
            () => { cts.Cancel(); return script.FinalizeAsync(UploadId, TxHashes); },
            log: TextWriter.Null,
            cancellationToken: cts.Token);

        await Assert.ThrowsAsync<TaskCanceledException>(() => run);
        Assert.Single(script.Calls);
    }

    [Fact]
    public async Task MaxAttemptsBelowOne_IsRejected()
    {
        var script = new ScriptedFinalize("unused");

        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(() => script.Run(maxAttempts: 0));
        Assert.Empty(script.Calls);
    }
}
