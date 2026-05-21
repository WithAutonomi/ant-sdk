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
 */
public record FilePutResult(
        String dataMap,
        String storageCostAtto,
        String gasCostWei,
        long chunksStored,
        String paymentModeUsed) {}
