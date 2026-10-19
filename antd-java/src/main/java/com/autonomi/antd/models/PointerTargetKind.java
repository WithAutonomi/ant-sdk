package com.autonomi.antd.models;

import java.util.Optional;

/**
 * What a pointer points at.
 *
 * <p>Pass as a typed parameter to the pointer write methods. The client
 * serializes the enum to the wire string at the request boundary.
 */
public enum PointerTargetKind {
    /** An immutable chunk, such as a public file's data map. The default. */
    CHUNK("chunk", 0),
    /**
     * Another pointer: a forwarding the owner can still change. Use a
     * transfer to hand a pointer over for good.
     */
    POINTER("pointer", 1);

    private final String wire;
    private final int tag;

    PointerTargetKind(String wire, int tag) {
        this.wire = wire;
        this.tag = tag;
    }

    /** Serialize to the wire string the daemon expects. */
    public String wireValue() {
        return wire;
    }

    /** The raw target tag the network stores for this kind. */
    public int tag() {
        return tag;
    }

    /**
     * The kind a raw target tag names, or empty for a tag this SDK does not
     * know ({@code 0} chunk, {@code 1} pointer).
     *
     * @param tag the raw target tag
     * @return the kind, or empty when the tag is unknown
     */
    public static Optional<PointerTargetKind> fromTag(int tag) {
        for (PointerTargetKind k : values()) {
            if (k.tag == tag) return Optional.of(k);
        }
        return Optional.empty();
    }
}
