<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * A pointer write for the daemon to sign with its loaded owner key and quote
 * for an external signer (`pointerPrepare()`).
 *
 * Build it with {@see create()}, {@see update()} or {@see transfer()}. The
 * daemon checks the combination; a create or update without a target, or a
 * transfer without a recipient, is a {@see \Autonomi\Antd\Errors\BadRequestError}.
 *
 * Pass `includeSignedQuotes: true` to also get the full signed quotes in
 * {@see PointerPrepareResult::$signedQuotes}, for offline verification. It is
 * off by default and sent only when true.
 */
readonly class PointerPrepareRequest
{
    public function __construct(
        /** Address of the pointer to write; the daemon must hold its key. */
        public string $owner,
        /** The write to sign. */
        public PointerOp $op,
        /** Create / update: the address to point at. */
        public ?string $target = null,
        /** Create / update: what the target is; null leaves the daemon's default (chunk). */
        public ?PointerTargetKind $kind = null,
        /** Transfer: the recipient's pointer, which must already exist. */
        public ?string $recipient = null,
        /** Ask for the full signed quotes in the result; off by default. */
        public bool $includeSignedQuotes = false,
    ) {}

    /** Create the pointer at `$owner`, pointing at `$target`. */
    public static function create(string $owner, string $target, ?PointerTargetKind $kind = null, bool $includeSignedQuotes = false): self
    {
        return new self($owner, PointerOp::Create, target: $target, kind: $kind, includeSignedQuotes: $includeSignedQuotes);
    }

    /** Point the pointer at `$owner` at `$target`, creating it if it does not exist. */
    public static function update(string $owner, string $target, ?PointerTargetKind $kind = null, bool $includeSignedQuotes = false): self
    {
        return new self($owner, PointerOp::Update, target: $target, kind: $kind, includeSignedQuotes: $includeSignedQuotes);
    }

    /** Hand the pointer at `$owner` over for good to the pointer at `$recipient`. */
    public static function transfer(string $owner, string $recipient, bool $includeSignedQuotes = false): self
    {
        return new self($owner, PointerOp::Transfer, recipient: $recipient, includeSignedQuotes: $includeSignedQuotes);
    }

    /**
     * The JSON body for `POST /v1/pointers/prepare`; null fields are left out.
     *
     * @return array<string, string|bool>
     */
    public function toArray(): array
    {
        $body = ['owner' => $this->owner, 'op' => $this->op->value];
        if ($this->target !== null) {
            $body['target'] = $this->target;
        }
        if ($this->kind !== null) {
            $body['kind'] = $this->kind->value;
        }
        if ($this->recipient !== null) {
            $body['recipient'] = $this->recipient;
        }
        if ($this->includeSignedQuotes) {
            $body['include_signed_quotes'] = true;
        }
        return $body;
    }
}
