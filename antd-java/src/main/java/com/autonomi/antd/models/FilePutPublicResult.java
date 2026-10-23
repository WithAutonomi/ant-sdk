package com.autonomi.antd.models;

/**
 * Result of a public file upload. The DataMap is stored on-network as an
 * extra chunk; {@code address} is the shareable retrieval handle.
 *
 * @param address          hex-encoded on-network DataMap address
 * @param storageCostAtto  total storage cost paid in atto tokens ("0" if all chunks already existed)
 * @param gasCostWei       total gas cost paid in wei as a decimal string
 * @param chunksStored     number of chunks stored on the network
 * @param paymentModeUsed  which payment mode was actually used
 * @param sha256           the plaintext's SHA-256 (hex, lowercase); {@code null}
 *                         on antd before 0.17.0
 */
public record FilePutPublicResult(
        String address,
        String storageCostAtto,
        String gasCostWei,
        long chunksStored,
        String paymentModeUsed,
        String sha256) {

    /** Backward-compatible constructor without {@code sha256} (defaults to {@code null}). */
    public FilePutPublicResult(
            String address,
            String storageCostAtto,
            String gasCostWei,
            long chunksStored,
            String paymentModeUsed) {
        this(address, storageCostAtto, gasCostWei, chunksStored, paymentModeUsed, null);
    }
}
