package com.autonomi.antd.models;

/**
 * One frame of a progress-enabled streaming download: the total download size,
 * a plaintext data chunk, or a {@link DownloadProgress} update. Returned by the
 * {@code *WithProgress} streaming methods; the plain {@code dataStream} /
 * {@code dataStreamPublic} methods stay a pure {@code InputStream} of bytes for
 * callers that don't need progress.
 *
 * <p>Exactly one arm is set per frame: a meta frame has {@code isMeta() == true}
 * and carries the byte total via {@link #totalSize()}; a data frame has a
 * non-null {@link #data()} (and {@code isProgress() == false}); a progress frame
 * has a non-null {@link #progress()} and {@code isProgress() == true}.
 *
 * <p>The meta frame is the progress denominator, in bytes — surfaced from the
 * gRPC {@code x-content-length} response header or the REST NDJSON {@code meta}
 * frame. It is emitted at most once, before any data.
 */
public final class DownloadFrame {

    private final byte[] data;
    private final DownloadProgress progress;
    private final long totalSize;
    private final boolean meta;

    private DownloadFrame(byte[] data, DownloadProgress progress, long totalSize, boolean meta) {
        this.data = data;
        this.progress = progress;
        this.totalSize = totalSize;
        this.meta = meta;
    }

    /** Creates a data frame carrying a decrypted plaintext chunk. */
    public static DownloadFrame ofData(byte[] data) {
        return new DownloadFrame(data, null, 0L, false);
    }

    /** Creates a progress frame carrying a fetch-progress update. */
    public static DownloadFrame ofProgress(DownloadProgress progress) {
        return new DownloadFrame(null, progress, 0L, false);
    }

    /**
     * Creates a meta frame carrying the total download size in bytes — the
     * progress denominator. Emitted at most once, before any data.
     */
    public static DownloadFrame ofMeta(long totalSize) {
        return new DownloadFrame(null, null, totalSize, true);
    }

    /** {@code true} if this frame carries the total-size denominator. */
    public boolean isMeta() {
        return meta;
    }

    /** {@code true} if this frame is a {@link DownloadProgress} update. */
    public boolean isProgress() {
        return progress != null;
    }

    /**
     * The total download size in bytes of a meta frame, or {@code 0} if this is
     * not a meta frame (see {@link #isMeta()}).
     */
    public long totalSize() {
        return totalSize;
    }

    /**
     * The plaintext bytes of a data frame, or {@code null} if this is a meta or
     * progress frame (see {@link #isMeta()}, {@link #isProgress()}).
     */
    public byte[] data() {
        return data;
    }

    /**
     * The fetch-progress update of a progress frame, or {@code null} if this is a
     * meta or data frame (see {@link #isProgress()}).
     */
    public DownloadProgress progress() {
        return progress;
    }
}
