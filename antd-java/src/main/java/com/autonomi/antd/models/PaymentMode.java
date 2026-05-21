package com.autonomi.antd.models;

/**
 * Payment-batching strategy for uploads.
 *
 * <ul>
 *   <li>{@link #AUTO}   — server picks (merkle for 64+ chunks, single otherwise).</li>
 *   <li>{@link #MERKLE} — force merkle-batch (saves gas, min 2 chunks).</li>
 *   <li>{@link #SINGLE} — force per-chunk payments (works for any chunk count).</li>
 * </ul>
 *
 * <p>Pass as a typed parameter to put/cost methods. The client serializes the
 * enum to the wire string at the request boundary.
 */
public enum PaymentMode {
    AUTO("auto"),
    MERKLE("merkle"),
    SINGLE("single");

    private final String wire;

    PaymentMode(String wire) {
        this.wire = wire;
    }

    /** Serialize to the wire string the daemon expects. */
    public String wireValue() {
        return wire;
    }
}
