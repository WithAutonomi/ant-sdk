package com.autonomi.antd.models;

import java.util.Arrays;
import java.util.List;
import java.util.Objects;

/**
 * The result of {@code buildManifest}. Nothing was uploaded: store or share
 * the bytes or the link yourself.
 *
 * @param manifest the {@code .ant} bytes (raw; REST's base64 is decoded)
 * @param link     the {@code ant://manifest/} link, or {@code null} when it does
 *                 not fit the recommended 1,500 bytes
 * @param entries  the entries in encoded order (sorted by effective name)
 */
public record BuiltManifest(byte[] manifest, String link, List<ManifestEntryInfo> entries) {

    /** Compares the bytes by content, not identity. */
    @Override
    public boolean equals(Object o) {
        return o instanceof BuiltManifest b
                && Arrays.equals(manifest, b.manifest)
                && Objects.equals(link, b.link)
                && Objects.equals(entries, b.entries);
    }

    @Override
    public int hashCode() {
        return 31 * (31 * Arrays.hashCode(manifest) + Objects.hashCode(link)) + Objects.hashCode(entries);
    }

    @Override
    public String toString() {
        return "BuiltManifest[manifest=" + (manifest == null ? "null" : manifest.length + " bytes")
                + ", link=" + link + ", entries=" + entries + "]";
    }
}
