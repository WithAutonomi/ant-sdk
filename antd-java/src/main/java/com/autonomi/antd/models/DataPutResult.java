package com.autonomi.antd.models;

/**
 * Result of a private data put. The DataMap is returned to the caller; it is
 * NOT stored on-network. The REST transport populates {@code chunksStored}
 * and {@code paymentModeUsed}; the gRPC transport currently leaves them
 * empty (proto {@code PutDataResponse} only carries {@code data_map}).
 *
 * @param dataMap         hex-encoded caller-held DataMap
 * @param chunksStored    number of chunks stored on the network
 * @param paymentModeUsed which payment mode was actually used: "auto", "merkle", or "single"
 */
public record DataPutResult(
        String dataMap,
        long chunksStored,
        String paymentModeUsed) {
    public DataPutResult(String dataMap) {
        this(dataMap, 0L, "");
    }
}
