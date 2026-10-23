package com.autonomi.antd.models;

/**
 * What a manifest says about one entry ({@code buildManifest},
 * {@code decodeManifest}, {@code decodeManifestLink}). Unset values are
 * {@code null} on both transports, never {@code 0} or the empty string.
 *
 * @param effectiveName  {@code path}, or the content address in hex when there
 *                       is none
 * @param path           the entry's relative path, or {@code null}
 * @param size           the size recorded in the manifest (the creator's
 *                       claim), or {@code null} when none was recorded
 * @param kind           {@value #KIND_EMBEDDED} or {@value #KIND_PUBLIC}
 * @param contentAddress the file's public DataMap address (hex), whether or not
 *                       it was ever made public; the same for private and
 *                       public uploads of one file
 * @param dataMap        the embedded DataMap in the hex form the download
 *                       methods accept. Decode only: {@code null} for public
 *                       entries and on build.
 * @param exactSize      the exact plaintext size, from an embedded root
 *                       DataMap or after a resolving decode; otherwise
 *                       {@code null}
 * @param error          why a resolving decode failed for this entry, or
 *                       {@code null}. One entry's failure does not fail the
 *                       call.
 * @param sha256         the plaintext's SHA-256 (hex, lowercase) recorded for the
 *                       entry, or {@code null} when none (or antd before 0.17.0)
 */
public record ManifestEntryInfo(
        String effectiveName,
        String path,
        Long size,
        String kind,
        String contentAddress,
        String dataMap,
        Long exactSize,
        String error,
        String sha256) {

    /** Backward-compatible constructor without {@code sha256} (defaults to {@code null}). */
    public ManifestEntryInfo(
            String effectiveName,
            String path,
            Long size,
            String kind,
            String contentAddress,
            String dataMap,
            Long exactSize,
            String error) {
        this(effectiveName, path, size, kind, contentAddress, dataMap, exactSize, error, null);
    }

    /** The {@link #kind()} of an entry that embeds its DataMap. */
    public static final String KIND_EMBEDDED = "embedded";

    /** The {@link #kind()} of an entry that refers to a public DataMap address. */
    public static final String KIND_PUBLIC = "public";

    /**
     * Whether the entry embeds its DataMap.
     *
     * @return {@code kind} is {@value #KIND_EMBEDDED}
     */
    public boolean isEmbedded() {
        return KIND_EMBEDDED.equals(kind);
    }
}
