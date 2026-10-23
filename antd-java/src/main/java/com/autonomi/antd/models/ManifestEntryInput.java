package com.autonomi.antd.models;

/**
 * One file for {@code buildManifest}. Set exactly one of {@code dataMap} or
 * {@code address}; the client rejects an entry with both or neither before
 * anything is sent. {@code null} and the empty string both mean unset.
 *
 * <pre>{@code
 * ManifestEntryInput.ofAddress(address).withPath("notes/one.txt");
 * ManifestEntryInput.ofDataMap(dataMap).withPath("secret.txt").withSize(82L);
 * }</pre>
 *
 * @param path    the relative path the entry extracts under, subject to the
 *                portable path rules; {@code null} (or empty) means it
 *                extracts under its content address
 * @param size    the plaintext size to record, as given (the creator's
 *                claim); {@code null} records none, and readers take the
 *                exact size from an embedded root DataMap. Must not be
 *                negative.
 * @param dataMap a hex DataMap, as the upload methods return it. The entry
 *                embeds it: the manifest is the key to the file.
 * @param address a public file's DataMap address (hex, 32 bytes)
 */
public record ManifestEntryInput(String path, Long size, String dataMap, String address) {

    /**
     * An entry that embeds a DataMap.
     *
     * @param dataMap a hex DataMap, as the upload methods return it
     * @return an entry with no path and no size
     */
    public static ManifestEntryInput ofDataMap(String dataMap) {
        return new ManifestEntryInput(null, null, dataMap, null);
    }

    /**
     * An entry that refers to a public file by its DataMap address.
     *
     * @param address the public DataMap address (hex, 32 bytes)
     * @return an entry with no path and no size
     */
    public static ManifestEntryInput ofAddress(String address) {
        return new ManifestEntryInput(null, null, null, address);
    }

    /**
     * This entry with another path.
     *
     * @param path the relative path, or {@code null} for none
     * @return a copy with {@code path} set
     */
    public ManifestEntryInput withPath(String path) {
        return new ManifestEntryInput(path, size, dataMap, address);
    }

    /**
     * This entry with another recorded size.
     *
     * @param size the plaintext size to record, or {@code null} for none
     * @return a copy with {@code size} set
     */
    public ManifestEntryInput withSize(Long size) {
        return new ManifestEntryInput(path, size, dataMap, address);
    }
}
