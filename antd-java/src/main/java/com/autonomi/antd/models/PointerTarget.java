package com.autonomi.antd.models;

import java.util.Optional;

/**
 * Where a chain of pointers ends ({@code pointerResolve}).
 *
 * @param kind    {@code "chunk"}, or {@code "unknown"} for a target kind the
 *                daemon does not know
 * @param kindTag the raw target tag
 * @param target  the address at the end of the chain (hex)
 */
public record PointerTarget(String kind, int kindTag, String target) {

    /**
     * The target's kind.
     *
     * @return the kind, or empty when this SDK does not know the tag
     */
    public Optional<PointerTargetKind> targetKind() {
        return PointerTargetKind.fromTag(kindTag);
    }
}
