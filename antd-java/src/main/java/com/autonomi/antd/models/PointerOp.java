package com.autonomi.antd.models;

import java.util.Objects;

/**
 * The write a {@code pointerPrepare} signs for an external signer to pay:
 * {@link Create}, {@link Update} or {@link Transfer}.
 */
public sealed interface PointerOp {

    /**
     * The op's wire name.
     *
     * @return {@code "create"}, {@code "update"} or {@code "transfer"}
     */
    String wireName();

    /**
     * Create the pointer at {@code target}. Refused if it already exists.
     *
     * @param target the address to point at (hex)
     * @param kind   what {@code target} is; {@code null} means
     *               {@link PointerTargetKind#CHUNK}
     */
    record Create(String target, PointerTargetKind kind) implements PointerOp {
        /** Validates the target and defaults the kind to {@link PointerTargetKind#CHUNK}. */
        public Create {
            Objects.requireNonNull(target, "target");
            if (kind == null) kind = PointerTargetKind.CHUNK;
        }

        @Override
        public String wireName() {
            return "create";
        }
    }

    /**
     * Point the pointer at {@code target}, creating it if it does not exist.
     *
     * @param target the address to point at (hex)
     * @param kind   what {@code target} is; {@code null} means
     *               {@link PointerTargetKind#CHUNK}
     */
    record Update(String target, PointerTargetKind kind) implements PointerOp {
        /** Validates the target and defaults the kind to {@link PointerTargetKind#CHUNK}. */
        public Update {
            Objects.requireNonNull(target, "target");
            if (kind == null) kind = PointerTargetKind.CHUNK;
        }

        @Override
        public String wireName() {
            return "update";
        }
    }

    /**
     * Hand the pointer over for good to the pointer at {@code recipient},
     * which must already exist. Irreversible once stored.
     *
     * @param recipient the recipient pointer's address (hex)
     */
    record Transfer(String recipient) implements PointerOp {
        /** Validates the recipient. */
        public Transfer {
            Objects.requireNonNull(recipient, "recipient");
        }

        @Override
        public String wireName() {
            return "transfer";
        }
    }

    /**
     * A {@link Create} of a target of the given kind.
     *
     * @param target the address to point at (hex)
     * @param kind   what {@code target} is; {@code null} means chunk
     * @return the op
     */
    static PointerOp create(String target, PointerTargetKind kind) {
        return new Create(target, kind);
    }

    /**
     * An {@link Update} to a target of the given kind.
     *
     * @param target the address to point at (hex)
     * @param kind   what {@code target} is; {@code null} means chunk
     * @return the op
     */
    static PointerOp update(String target, PointerTargetKind kind) {
        return new Update(target, kind);
    }

    /**
     * A {@link Transfer} to the recipient's pointer.
     *
     * @param recipient the recipient pointer's address (hex)
     * @return the op
     */
    static PointerOp transfer(String recipient) {
        return new Transfer(recipient);
    }
}
