package com.autonomi.antd.models;

/**
 * Options for {@code pointerPrepare}.
 *
 * @param includeSignedQuotes ask the daemon to return each quote in full
 *                            signed form ({@link PointerPrepareResult#signedQuotes()})
 *                            for offline verification. A daemon without the
 *                            feature ignores it and the list stays empty.
 */
public record PointerPrepareOptions(boolean includeSignedQuotes) {

    /** The defaults: no signed quotes. */
    public static final PointerPrepareOptions DEFAULT = new PointerPrepareOptions(false);
}
