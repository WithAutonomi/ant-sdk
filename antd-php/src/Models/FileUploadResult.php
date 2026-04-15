<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Result of a public file or directory upload.
 *
 * Returned by AntdClient::fileUploadPublic() and AntdClient::dirUploadPublic()
 * (and their Async variants).
 */
readonly class FileUploadResult
{
    public function __construct(
        /** Hex-encoded network address of the uploaded file/directory. */
        public string $address,
        /** Total storage cost paid in token units (atto). "0" if all chunks already existed. */
        public string $storageCostAtto,
        /** Total gas cost paid in wei as a decimal string. */
        public string $gasCostWei,
        /** Number of chunks stored on the network (uint64). */
        public int $chunksStored,
        /** Which payment mode was actually used: "auto", "merkle", or "single". */
        public string $paymentModeUsed,
    ) {}
}
