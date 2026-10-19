package com.autonomi.antd.models;

import java.math.BigInteger;
import java.util.List;

/**
 * A pointer write signed by the daemon and quoted for an external signer
 * ({@code pointerPrepare}). Pay {@link #payments()} with {@code payForQuotes()},
 * then call {@code pointerFinalize} with {@link #uploadId()}.
 *
 * <p>While it awaits payment, other writes to the pointer throw
 * {@link com.autonomi.antd.errors.ConflictException} until it is finalized or
 * expires (the daemon keeps a prepared write for an hour).
 *
 * @param uploadId            identifier to pass to {@code pointerFinalize}
 * @param op                  {@code "create"}, {@code "update"} or {@code "transfer"}
 * @param address             the pointer's address (hex)
 * @param stateId             the signed state's identifier (hex)
 * @param counter             the signed state's counter (unsigned 64-bit; a
 *                            transfer is at {@link PointerRecord#FINAL_COUNTER})
 * @param paymentType         always {@code "wave_batch"}: a pointer state is
 *                            paid with one quote
 * @param payments            the quotes to pay with {@code payForQuotes()}
 * @param totalAmount         total to pay (atto tokens, decimal string)
 * @param paymentVaultAddress payment vault contract address
 * @param paymentTokenAddress payment token contract address
 * @param rpcUrl              EVM RPC URL for submitting transactions
 * @param signedQuotes        the quotes in full signed form, when asked for
 *                            with {@link PointerPrepareOptions#includeSignedQuotes()};
 *                            otherwise empty
 */
public record PointerPrepareResult(
        String uploadId,
        String op,
        String address,
        String stateId,
        BigInteger counter,
        String paymentType,
        List<PaymentInfo> payments,
        String totalAmount,
        String paymentVaultAddress,
        String paymentTokenAddress,
        String rpcUrl,
        List<SignedQuoteEntry> signedQuotes) {}
