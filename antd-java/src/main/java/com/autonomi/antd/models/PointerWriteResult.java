package com.autonomi.antd.models;

import java.math.BigInteger;

/**
 * The state a pointer write stored ({@code pointerCreate} / {@code pointerUpdate}).
 *
 * @param address the pointer's address (hex, 64 chars)
 * @param stateId the stored state's identifier, the one it was paid against (hex)
 * @param counter the state's counter, an unsigned 64-bit value. A final state
 *                (a transfer) sits at {@link PointerRecord#FINAL_COUNTER}.
 */
public record PointerWriteResult(String address, String stateId, BigInteger counter) {}
