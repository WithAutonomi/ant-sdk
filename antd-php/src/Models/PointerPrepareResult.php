<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * A pointer write signed by the daemon and quoted for an external signer
 * (`pointerPrepare()`): the same wave-batch payment shape
 * `prepareChunkUpload()` returns. Pay `$payments` with `payForQuotes()`, then
 * call `pointerFinalize()`.
 *
 * While it awaits payment, other writes to the pointer throw
 * {@see \Autonomi\Antd\Errors\ConflictError} until it is finalized or expires
 * (the daemon's one-hour pending TTL).
 */
readonly class PointerPrepareResult
{
    public function __construct(
        /** Opaque server-side identifier to pass back to pointerFinalize(). */
        public string $uploadId,
        /** `"create"`, `"update"` or `"transfer"`. */
        public string $op,
        /** The pointer's address (hex). */
        public string $address,
        /** The signed state's identifier (hex). */
        public string $stateId,
        /** The signed state's counter, as a canonical decimal string ({@see PointerCounter}). */
        public string $counter,
        /** Always `"wave_batch"`: a pointer state is paid with one quote. */
        public string $paymentType,
        /** @var list<PaymentInfo> Per-quote payments the external signer must submit. */
        public array $payments,
        /** Total atto-token amount across all entries in $payments. */
        public string $totalAmount,
        /** Payment vault contract address (hex with 0x prefix). */
        public string $paymentVaultAddress,
        /** Payment token contract address (hex with 0x prefix). */
        public string $paymentTokenAddress,
        /** EVM RPC URL the external signer should submit transactions through. */
        public string $rpcUrl,
        /** @var list<SignedQuoteEntry> Full signed quotes; filled when the request set `includeSignedQuotes` and payment is required, otherwise empty. */
        public array $signedQuotes = [],
    ) {}
}
