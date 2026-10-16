package com.autonomi.antd.models;

import java.util.List;

/**
 * The optional parts of a {@code buildManifest} call. {@link #DEFAULT} (or
 * {@code null}) means no name, no torrent info hashes, and embedded roots.
 *
 * @param name               a suggested root directory name (one portable
 *                           path component); {@code null} or empty for none
 * @param torrentInfoHashes  BitTorrent info hashes of the same files: hex, 40
 *                           characters for v1 and/or 64 for v2. {@code null}
 *                           reads as empty.
 * @param keepShrunkDataMaps embed shrunk DataMaps exactly as given. By default
 *                           ({@code false}) the daemon resolves each one's root
 *                           (fetching its wrapper records) and embeds the root
 *                           when it is at most 64 KiB, so recipients skip that
 *                           fetch (ADR-0006's policy). Sent as
 *                           {@code embed_roots = !keepShrunkDataMaps}.
 */
public record BuildManifestOptions(String name, List<String> torrentInfoHashes, boolean keepShrunkDataMaps) {

    /** The defaults: no name, no torrent info hashes, roots embedded. */
    public static final BuildManifestOptions DEFAULT = new BuildManifestOptions(null, List.of(), false);

    /** Copies {@code torrentInfoHashes}, reading {@code null} as empty. */
    public BuildManifestOptions {
        torrentInfoHashes = torrentInfoHashes == null ? List.of() : List.copyOf(torrentInfoHashes);
    }

    /**
     * These options with another root directory name.
     *
     * @param name the suggested root directory name, or {@code null} for none
     * @return a copy with {@code name} set
     */
    public BuildManifestOptions withName(String name) {
        return new BuildManifestOptions(name, torrentInfoHashes, keepShrunkDataMaps);
    }

    /**
     * These options with other torrent info hashes.
     *
     * @param torrentInfoHashes hex info hashes (v1 and/or v2)
     * @return a copy with {@code torrentInfoHashes} set
     */
    public BuildManifestOptions withTorrentInfoHashes(List<String> torrentInfoHashes) {
        return new BuildManifestOptions(name, torrentInfoHashes, keepShrunkDataMaps);
    }

    /**
     * These options with root embedding switched off or on.
     *
     * @param keepShrunkDataMaps {@code true} to embed shrunk DataMaps as given
     * @return a copy with {@code keepShrunkDataMaps} set
     */
    public BuildManifestOptions withKeepShrunkDataMaps(boolean keepShrunkDataMaps) {
        return new BuildManifestOptions(name, torrentInfoHashes, keepShrunkDataMaps);
    }
}
