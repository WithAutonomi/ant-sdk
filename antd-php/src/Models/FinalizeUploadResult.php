<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Result of finalizing an externally-signed upload.
 *
 * `dataMap` is always populated — it's the hex-encoded msgpack of the
 * underlying DataMap. `address` is only set when the legacy
 * `store_data_map=true` flag asked the daemon to pay+store the DataMap from
 * its own wallet (this PHP client doesn't expose that flag). `dataMapAddress`
 * is set when the prepare call used `visibility="public"` — in that case the
 * DataMap chunk was bundled into the same external-signer payment batch and
 * the returned address is the shareable retrieval handle. Defaults to "" when
 * talking to a pre-0.6.1 daemon that doesn't include the field.
 */
readonly class FinalizeUploadResult
{
    public function __construct(
        /** Hex-encoded msgpack DataMap (always returned). */
        public string $dataMap,
        /** Legacy: hex network address when store_data_map=true was passed (paid by daemon wallet). */
        public string $address,
        /** Hex network address when prepare used visibility="public" (paid in the external-signer batch). */
        public string $dataMapAddress,
        /** Number of chunks stored on the network. */
        public int $chunksStored,
    ) {}
}
