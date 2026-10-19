package com.autonomi.antd.models;

/**
 * What a transfer stored, and where the close group says it stands
 * ({@code pointerTransfer}).
 *
 * @param address       the pointer's address (hex)
 * @param stateId       the stored final state's identifier (hex)
 * @param finality      the close group's view once the write landed, or
 *                      {@code null} when that check failed. A failed check
 *                      does not undo the transfer: it is stored and final. Ask
 *                      again with {@code pointerFinality}.
 * @param finalityError why the check failed, when {@code finality} is
 *                      {@code null}; otherwise {@code null}
 */
public record PointerTransferResult(
        String address,
        String stateId,
        PointerFinality finality,
        String finalityError) {}
