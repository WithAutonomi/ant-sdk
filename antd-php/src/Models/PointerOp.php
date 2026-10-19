<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * The write a pointer prepare signs for an external signer to pay. The
 * backing string is the daemon's wire value for `op`.
 */
enum PointerOp: string
{
    /** Create the pointer at a target. Refused if it already exists. */
    case Create = 'create';
    /** Point the pointer at a target, creating it if it does not exist. */
    case Update = 'update';
    /** Hand the pointer over for good to an existing recipient pointer. Irreversible. */
    case Transfer = 'transfer';
}
