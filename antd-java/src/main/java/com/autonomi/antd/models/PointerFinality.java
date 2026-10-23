package com.autonomi.antd.models;

import java.math.BigInteger;
import java.util.List;

/**
 * The whole close group's view of a pointer's finality ({@code pointerFinality}).
 * Check it before relying on a transfer: only {@link #isFinal()} means the
 * transfer is beyond dispute.
 *
 * <p>Unset values are {@code null} on both transports (REST sends JSON
 * {@code null}; gRPC an empty string or an absent message).
 *
 * @param address       the pointer's address (hex)
 * @param group         peers in the close group
 * @param answered      peers that answered
 * @param status        the status; {@link PointerFinalityStatus#UNKNOWN} for one
 *                      this SDK does not know
 * @param rawStatus     the daemon's status string, always set
 * @param counter       {@link PointerFinalityStatus#OPEN} only: the counter a
 *                      read would return, when a state is corroborated;
 *                      otherwise {@code null}
 * @param state         {@code SETTLING}, {@code UNCONFIRMED} and {@code FINAL}:
 *                      the one final state seen; otherwise {@code null}
 * @param states        {@code FORKED} only: every final state seen, most-held
 *                      first; otherwise empty
 * @param majority      {@code FORKED} only: the state a majority holds, which
 *                      reads return; otherwise {@code null}
 * @param transferredTo the pointer this one was handed over to, once that is
 *                      beyond dispute (status {@code FINAL}); otherwise
 *                      {@code null}
 */
public record PointerFinality(
        String address,
        int group,
        int answered,
        PointerFinalityStatus status,
        String rawStatus,
        BigInteger counter,
        PointerFinalState state,
        List<PointerFinalState> states,
        PointerFinalState majority,
        String transferredTo) {

    /**
     * Whether the close group reports one final state, held by a majority,
     * with every peer answering and no rival seen.
     *
     * @return {@code true} when {@link #status()} is {@link PointerFinalityStatus#FINAL}
     */
    public boolean isFinal() {
        return status == PointerFinalityStatus.FINAL;
    }
}
