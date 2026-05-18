package com.autonomi.antd.models;

/**
 * Result of finalizing an externally-signed upload.
 *
 * <p>{@code dataMap} and {@code dataMapAddress} were added in antd 0.6.1.
 * When prepare was called with {@code visibility="public"}, the DataMap chunk
 * is bundled into the same external-signer payment batch and stored on-network
 * — {@code dataMapAddress} is then the shareable retrieval handle. For
 * private/legacy uploads both fields are empty strings.
 *
 * @param address        legacy: set when {@code store_data_map=true} was passed
 *                       (paid by the daemon wallet). Empty otherwise.
 * @param chunksStored   number of chunks stored on the network
 * @param dataMap        hex-encoded serialized DataMap; always returned by
 *                       0.6.1+ daemons, empty when talking to older ones
 * @param dataMapAddress hex retrieval address of the DataMap chunk; set when
 *                       prepare was called with {@code visibility="public"},
 *                       empty otherwise
 */
public record FinalizeUploadResult(
        String address,
        long chunksStored,
        String dataMap,
        String dataMapAddress) {

    /**
     * Backward-compatible constructor for callers that only need the original
     * two fields. {@code dataMap} and {@code dataMapAddress} default to empty.
     */
    public FinalizeUploadResult(String address, long chunksStored) {
        this(address, chunksStored, "", "");
    }
}
