package com.autonomi.antd.models;

/**
 * Where a pointer stands with respect to finality, as its whole close group
 * reports it. {@link PointerFinality#rawStatus()} keeps the daemon's string,
 * so a status this SDK does not know ({@link #UNKNOWN}) is not lost.
 */
public enum PointerFinalityStatus {
    /**
     * No peer that answered holds a final state: the owner can still move the
     * pointer. Rules a final state out only when every peer answered.
     */
    OPEN("open"),
    /**
     * One final state, not yet held by a majority: a transfer still spreading,
     * or a write that fell short.
     */
    SETTLING("settling"),
    /**
     * One final state held by a majority, but not every peer answered, so a
     * rival could still be unseen. Ask again.
     */
    UNCONFIRMED("unconfirmed"),
    /**
     * One final state held by a majority, every peer answered, no rival. The
     * only status a recipient should rely on.
     */
    FINAL("final"),
    /** The owner signed two or more different final states. */
    FORKED("forked"),
    /**
     * A status this SDK does not know (a newer daemon). The daemon's string is
     * in {@link PointerFinality#rawStatus()}.
     */
    UNKNOWN(null);

    private final String wire;

    PointerFinalityStatus(String wire) {
        this.wire = wire;
    }

    /**
     * The daemon's wire string.
     *
     * @return the wire string, or {@code null} for {@link #UNKNOWN}
     */
    public String wireValue() {
        return wire;
    }

    /**
     * Parses the daemon's wire string.
     *
     * @param s the wire string
     * @return the status; anything unrecognised is {@link #UNKNOWN}
     */
    public static PointerFinalityStatus fromWire(String s) {
        for (PointerFinalityStatus st : values()) {
            if (st.wire != null && st.wire.equals(s)) return st;
        }
        return UNKNOWN;
    }
}
