using Antd.Sdk;

namespace Antd.Examples;

/// <summary>
/// Bounded finalize retry for the external-signer flow (Example 07). Kept in
/// its own file so the SDK tests can compile it in and exercise it directly.
/// </summary>
public static class FinalizeRetry
{
    /// <summary>Attempts, the first included, before the helper gives up.</summary>
    public const int DefaultMaxAttempts = 5;

    /// <summary>
    /// Runs a finalize and, when the daemon reports a storage shortfall AFTER
    /// the payment settled, acts on the <see cref="PartialUploadException"/>:
    /// <list type="bullet">
    /// <item><description>
    /// <see cref="PartialUploadException.Retryable"/>: the daemon (antd 0.14.0
    /// and later) kept the paid attempt under <paramref name="uploadId"/>, so
    /// the helper calls <paramref name="finalize"/> again, with the same
    /// upload_id and the same payment artefacts, to store only the remainder:
    /// no re-prepare, no second signature, no double payment. The loop is
    /// bounded: a persistent failure (a chunk whose close group stays
    /// unreachable) throws on every call, so the helper stops after
    /// <paramref name="maxAttempts"/> attempts, or as soon as
    /// <see cref="PartialUploadException.ChunksFailed"/> stops shrinking. The
    /// attempt stays retained until the daemon's pending-upload TTL, so the
    /// caller can finalize again later.
    /// </description></item>
    /// <item><description>
    /// <see cref="PartialUploadException.RetentionKnown"/> but not
    /// <c>Retryable</c>: the daemon confirmed it kept nothing (for example a
    /// merkle finalize that deliberately left sub-batches unpaid). The helper
    /// stops; the caller re-prepares the same content, which skips the chunks
    /// already stored.
    /// </description></item>
    /// <item><description>
    /// Not <see cref="PartialUploadException.RetentionKnown"/>: the SDK could
    /// not tell whether the daemon kept the paid attempt (a daemon before
    /// antd 0.14.0 over REST, or an error it could not fully read). The
    /// daemon may still hold it, so the helper stops without re-preparing or
    /// paying; the caller keeps the upload_id and the original payment
    /// artefacts and reconciles before paying again.
    /// </description></item>
    /// </list>
    /// Whenever it stops on a partial upload, the helper rethrows the original
    /// <see cref="PartialUploadException"/> (so <c>catch (AntdException)</c>
    /// and <c>catch (NetworkException)</c> still match and the counts
    /// survive); any other exception propagates untouched. It only ever calls
    /// <paramref name="finalize"/>: it never re-prepares or pays.
    /// <paramref name="cancellationToken"/> stops the loop between attempts
    /// (the backoff is cancellable) with an
    /// <see cref="OperationCanceledException"/>; it does not cancel a finalize
    /// already in flight, because the SDK's finalize methods take no token.
    /// </summary>
    /// <param name="uploadId">The upload_id being finalized, for log lines.</param>
    /// <param name="finalize">The finalize call, with its arguments fixed.</param>
    /// <param name="maxAttempts">Attempts, the first included (at least 1).</param>
    /// <param name="backoff">
    /// Waits before the next attempt, given the attempt just made; defaults
    /// to <c>attempt * 2</c> seconds.
    /// </param>
    /// <param name="log">Where progress lines go; defaults to the console.</param>
    /// <param name="cancellationToken">Stops the loop between attempts.</param>
    public static async Task<T> FinalizeWithRetryAsync<T>(
        string uploadId,
        Func<Task<T>> finalize,
        int maxAttempts = DefaultMaxAttempts,
        Func<int, CancellationToken, Task>? backoff = null,
        TextWriter? log = null,
        CancellationToken cancellationToken = default)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(maxAttempts, 1);
        backoff ??= (attempt, ct) => Task.Delay(TimeSpan.FromSeconds(attempt * 2), ct);
        log ??= Console.Out;

        ulong lastFailed = 0;
        for (var attempt = 1; ; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                return await finalize(); // every chunk stored
            }
            catch (PartialUploadException ex) when (!ex.Retryable)
            {
                log.WriteLine(ex.RetentionKnown
                    ? $"finalize stored {ex.ChunksStored}/{ex.TotalChunks} chunks and the daemon kept nothing " +
                      $"under upload_id {uploadId}: re-prepare the same content (stored chunks are skipped)"
                    : $"finalize stored {ex.ChunksStored}/{ex.TotalChunks} chunks but whether the daemon kept the " +
                      $"paid attempt under upload_id {uploadId} is unknown: stopping without re-preparing or " +
                      "paying; keep the upload_id and payment artefacts and reconcile before paying again");
                throw;
            }
            catch (PartialUploadException ex)
            {
                var stalled = attempt > 1 && ex.ChunksFailed >= lastFailed;
                if (attempt >= maxAttempts || stalled)
                {
                    log.WriteLine(
                        $"finalize {(stalled ? "stalled" : "gave up")} after {attempt} attempt(s): " +
                        $"{ex.ChunksStored}/{ex.TotalChunks} chunks stored, {ex.ChunksFailed} still unstored; " +
                        $"the paid attempt stays retained under upload_id {uploadId} until the daemon's " +
                        "pending-upload TTL, so finalize again later with the same arguments");
                    throw;
                }
                lastFailed = ex.ChunksFailed;
                log.WriteLine(
                    $"finalize stored {ex.ChunksStored}/{ex.TotalChunks} chunks, {ex.ChunksFailed} still unstored; " +
                    $"retrying against the same payment (attempt {attempt + 1}/{maxAttempts})");
                await backoff(attempt, cancellationToken);
            }
        }
    }
}
