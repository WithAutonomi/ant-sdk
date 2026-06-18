package com.autonomi.antd.models;

/**
 * Result of a public data put. The DataMap is stored on-network as an extra
 * chunk; {@code address} is the shareable retrieval handle. Both REST and
 * gRPC populate {@code chunksStored} and {@code paymentModeUsed}.
 *
 * @param address         hex-encoded on-network DataMap address
 * @param chunksStored    number of chunks stored on the network
 * @param paymentModeUsed which payment mode was actually used
 */
public record DataPutPublicResult(
        String address,
        long chunksStored,
        String paymentModeUsed) {
    public DataPutPublicResult(String address) {
        this(address, 0L, "");
    }
}
