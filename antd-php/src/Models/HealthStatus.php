<?php

declare(strict_types=1);

namespace Autonomi\Antd\Models;

/**
 * Health check result from the antd daemon.
 *
 * The diagnostic fields ({@see $version}, {@see $evmNetwork},
 * {@see $uptimeSeconds}, {@see $buildCommit}, {@see $paymentTokenAddress},
 * {@see $paymentVaultAddress}) were added in antd 0.4.0. They default to
 * empty / 0 so the class stays constructable when talking to a pre-0.4.0
 * daemon that doesn't report them.
 */
readonly class HealthStatus
{
    public function __construct(
        public bool $ok,
        public string $network,
        public string $version = '',
        public string $evmNetwork = '',
        public int $uptimeSeconds = 0,
        public string $buildCommit = '',
        public string $paymentTokenAddress = '',
        public string $paymentVaultAddress = '',
    ) {}
}
