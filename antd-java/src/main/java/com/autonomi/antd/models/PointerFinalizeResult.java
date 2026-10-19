package com.autonomi.antd.models;

import java.math.BigInteger;

/**
 * The state a pointer finalize stored ({@code pointerFinalize}).
 *
 * @param address  the pointer's address (hex)
 * @param stateId  the stored state's identifier (hex)
 * @param counter  the stored state's counter (unsigned 64-bit)
 * @param finality transfers only: where the close group says the transfer
 *                 stands; {@code null} for a create or update
 */
public record PointerFinalizeResult(
        String address,
        String stateId,
        BigInteger counter,
        PointerFinality finality) {}
