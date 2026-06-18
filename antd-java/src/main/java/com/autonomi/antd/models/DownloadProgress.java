package com.autonomi.antd.models;

/**
 * A fetch-progress update emitted during a streaming download when progress is
 * requested. Counts are in <b>chunks</b>, not bytes — the byte denominator is
 * the download's total size ({@code x-content-length} over gRPC, the NDJSON
 * {@code meta} frame over REST). {@link #total} is {@code 0} while still unknown
 * (mid DataMap-resolution).
 *
 * <p>{@link #phase} is one of:
 * <ul>
 *   <li>{@code "resolving_map"} — walking the hierarchical DataMap to learn the
 *       chunk count</li>
 *   <li>{@code "resolved"} — DataMap resolved, {@link #total} now holds the real
 *       chunk count</li>
 *   <li>{@code "fetching"} — fetching data chunks; {@link #fetched}/{@link #total}
 *       advance the bar</li>
 * </ul>
 *
 * @param phase   the current download phase
 * @param fetched chunks fetched so far in the current phase
 * @param total   total chunks for the current phase, or {@code 0} if not yet known
 */
public record DownloadProgress(String phase, long fetched, long total) {}
