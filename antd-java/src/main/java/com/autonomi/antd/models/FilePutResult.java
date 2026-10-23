package com.autonomi.antd.models;

/**
 * Result of a private file upload. The DataMap is returned to the caller;
 * it is NOT stored on-network.
 *
 * @param dataMap          hex-encoded caller-held DataMap
 * @param storageCostAtto  total storage cost paid in atto tokens ("0" if all chunks already existed)
 * @param gasCostWei       total gas cost paid in wei as a decimal string
 * @param chunksStored     number of chunks stored on the network
 * @param paymentModeUsed  which payment mode was actually used: "auto", "merkle", or "single"
 * @param sha256           the plaintext's SHA-256 (hex, lowercase); {@code null}
 *                         on antd before 0.17.0
 */
public record FilePutResult(
        String dataMap,
        String storageCostAtto,
        String gasCostWei,
        long chunksStored,
        String paymentModeUsed,
        String sha256) {

    /** Backward-compatible constructor without {@code sha256} (defaults to {@code null}). */
    public FilePutResult(
            String dataMap,
            String storageCostAtto,
            String gasCostWei,
            long chunksStored,
            String paymentModeUsed) {
        this(dataMap, storageCostAtto, gasCostWei, chunksStored, paymentModeUsed, null);
    }
}
