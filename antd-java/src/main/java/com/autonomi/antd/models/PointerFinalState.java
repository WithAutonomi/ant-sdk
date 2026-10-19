package com.autonomi.antd.models;

import java.util.Optional;

/**
 * One final state, as a finality check reports it.
 *
 * @param stateId       the state's identifier (hex)
 * @param kind          {@code "chunk"}, {@code "pointer"} or {@code "unknown"}
 * @param kindTag       the raw target tag
 * @param target        the address the state points at (hex)
 * @param holders       how many peers of the close group hold it
 * @param transferredTo the pointer the state hands over to, or {@code null}
 */
public record PointerFinalState(
        String stateId,
        String kind,
        int kindTag,
        String target,
        int holders,
        String transferredTo) {

    /**
     * The target's kind.
     *
     * @return the kind, or empty when this SDK does not know the tag
     */
    public Optional<PointerTargetKind> targetKind() {
        return PointerTargetKind.fromTag(kindTag);
    }
}
