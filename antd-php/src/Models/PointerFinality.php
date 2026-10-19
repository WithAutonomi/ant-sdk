<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * The whole close group's view of a pointer's finality (`pointerFinality()`).
 * Check it before relying on a transfer: only {@see isFinal()} means the
 * transfer is beyond dispute.
 *
 * Fields that do not apply to the status are null (REST sends `null`; an
 * empty string reads as null too).
 */
readonly class PointerFinality
{
    public function __construct(
        /** The pointer's address (hex). */
        public string $address,
        /** Peers in the close group. */
        public int $group,
        /** Peers that answered. */
        public int $answered,
        /** The status; {@see PointerFinalityStatus::Unknown} for one this SDK does not know. */
        public PointerFinalityStatus $status,
        /** The status exactly as the daemon sent it (the Unknown arm's value). */
        public string $rawStatus,
        /**
         * Open only: the counter a read would return, if any state is
         * corroborated, as a canonical decimal string; otherwise null.
         */
        public ?string $counter,
        /** Settling, Unconfirmed and Final: the one final state seen; otherwise null. */
        public ?PointerFinalState $state,
        /** @var list<PointerFinalState> Forked only: every final state seen, most-held first. */
        public array $states,
        /** Forked only: the state a majority holds, which reads return; otherwise null. */
        public ?PointerFinalState $majority,
        /** The pointer this one was handed over to, once that is beyond dispute (status Final); otherwise null. */
        public ?string $transferredTo,
    ) {}

    /** One final state, held by a majority, with every peer answering and no rival seen. */
    public function isFinal(): bool
    {
        return $this->status === PointerFinalityStatus::Final;
    }
}
