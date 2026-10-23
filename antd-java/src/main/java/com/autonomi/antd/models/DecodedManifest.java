package com.autonomi.antd.models;

import java.util.List;

/**
 * The result of {@code decodeManifest} and {@code decodeManifestLink}. Unset
 * values are {@code null} on both transports.
 *
 * @param source            {@value #SOURCE_MANIFEST}, or
 *                          {@value #SOURCE_FILE_LINK} for a file link or bare
 *                          address (reported as one public entry with no path)
 * @param name              the suggested root directory name, or {@code null}
 * @param torrentInfoHashV1 the BitTorrent v1 info hash (hex), or {@code null}
 * @param torrentInfoHashV2 the BitTorrent v2 info hash (hex), or {@code null}
 * @param entries           the entries in encoded order (sorted by effective
 *                          name)
 */
public record DecodedManifest(
        String source,
        String name,
        String torrentInfoHashV1,
        String torrentInfoHashV2,
        List<ManifestEntryInfo> entries) {

    /** The {@link #source()} of {@code .ant} bytes or a manifest link. */
    public static final String SOURCE_MANIFEST = "manifest";

    /** The {@link #source()} of a file link or bare address. */
    public static final String SOURCE_FILE_LINK = "file_link";
}
