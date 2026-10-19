package com.autonomi.antd.models;

import java.math.BigInteger;
import java.util.Optional;

/**
 * A pointer's current state, as the network serves it ({@code pointerGet}).
 *
 * @param address       the pointer's address (hex, 64 chars)
 * @param owner         the owner's ML-DSA-65 public key (hex, 1,952 bytes). The
 *                      address is derived from it, so it is the proof of who
 *                      owns the pointer.
 * @param counter       the state's counter, an unsigned 64-bit value; a final
 *                      state sits at {@link #FINAL_COUNTER}
 * @param kind          {@code "chunk"}, {@code "pointer"}, or {@code "unknown"}
 *                      for a kind the daemon does not know; {@code kindTag}
 *                      carries the raw value either way
 * @param kindTag       the raw target tag
 * @param target        the address the pointer points at (hex)
 * @param stateId       the state's identifier (hex)
 * @param isFinal       {@code true} at the final counter: the pointer was
 *                      handed over or frozen, and nothing can replace this state
 * @param transferredTo the pointer this one was handed over to, when its final
 *                      state is a transfer; {@code null} otherwise
 */
public record PointerRecord(
        String address,
        String owner,
        BigInteger counter,
        String kind,
        int kindTag,
        String target,
        String stateId,
        boolean isFinal,
        String transferredTo) {

    /**
     * The counter of a pointer's final state, after a transfer or a freeze:
     * 2<sup>64</sup> - 1. Nothing can replace a state at this counter.
     */
    public static final BigInteger FINAL_COUNTER =
            BigInteger.ONE.shiftLeft(64).subtract(BigInteger.ONE);

    /**
     * The target's kind.
     *
     * @return the kind, or empty when this SDK does not know the tag
     */
    public Optional<PointerTargetKind> targetKind() {
        return PointerTargetKind.fromTag(kindTag);
    }
}
