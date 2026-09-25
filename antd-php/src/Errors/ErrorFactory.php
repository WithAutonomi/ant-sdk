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
     * The body is read strictly, so a malformed one degrades rather than
     * throwing: only the string `"PARTIAL_UPLOAD"` selects
     * {@see PartialUploadError} (any other `code`, or a body that is not a
     * JSON object, keeps the status mapping); a count is taken only from a
     * JSON non-negative integer and reads as 0 otherwise; `retryable` is
     * true only for the JSON boolean `true`.
     *
     * @param array<mixed>|null $body The decoded JSON error body, or null
     *     when the response was not JSON.
     */
    public static function fromResponse(int $code, string $message, ?array $body = null): AntdError
    {
        if (($body['code'] ?? null) === 'PARTIAL_UPLOAD') {
            return new PartialUploadError(
                $message,
                chunksStored: self::nonNegativeInt($body['chunks_stored'] ?? null),
                chunksFailed: self::nonNegativeInt($body['chunks_failed'] ?? null),
                totalChunks: self::nonNegativeInt($body['total_chunks'] ?? null),
                retryable: ($body['retryable'] ?? false) === true,
            );
        }
        return self::fromHttpStatus($code, $message);
    }

    /**
     * A `PARTIAL_UPLOAD` count: the value when it is a JSON non-negative
     * integer, otherwise 0. No `(int)` coercion, which would read `"1"`,
     * `true`, `1.5` and `["x"]` as 1 and let `-1` through. An integer too
     * large for PHP's int comes out of json_decode() as a float, so it
     * reads as 0 too.
     */
    private static function nonNegativeInt(mixed $value): int
    {
        return is_int($value) && $value >= 0 ? $value : 0;
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
