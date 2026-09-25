<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

class ErrorFactory
{
    /**
     * Create the appropriate error type for a daemon error response.
     *
     * Prefers the machine-readable `code` over the bare HTTP status where
     * they diverge: `PARTIAL_UPLOAD` arrives as a 502 that would otherwise
     * read as a generic {@see NetworkError}, and it carries structured counts
     * plus a `retryable` flag (absent on daemons older than 0.14.0, so it
     * defaults to `false`). Every other code keeps the status-based mapping
     * of {@see fromHttpStatus()}.
     *
     * @param array<string, mixed>|null $body The decoded JSON error body, or
     *     null when the response was not JSON.
     */
    public static function fromResponse(int $code, string $message, ?array $body = null): AntdError
    {
        if (($body['code'] ?? null) === 'PARTIAL_UPLOAD') {
            return new PartialUploadError(
                $message,
                chunksStored: (int)($body['chunks_stored'] ?? 0),
                chunksFailed: (int)($body['chunks_failed'] ?? 0),
                totalChunks: (int)($body['total_chunks'] ?? 0),
                retryable: ($body['retryable'] ?? false) === true,
            );
        }
        return self::fromHttpStatus($code, $message);
    }

    /**
     * Create the appropriate error type for an HTTP status code.
     */
    public static function fromHttpStatus(int $code, string $message): AntdError
    {
        return match ($code) {
            400 => new BadRequestError($message),
            402 => new PaymentError($message),
            404 => new NotFoundError($message),
            409 => new AlreadyExistsError($message),
            413 => new TooLargeError($message),
            500 => new InternalError($message),
            502 => new NetworkError($message),
            503 => new ServiceUnavailableError($message),
            default => new AntdError($code, $message ?? ''),
        };
    }
}
