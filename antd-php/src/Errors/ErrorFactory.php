<?php

declare(strict_types=1);

namespace Autonomi\Antd\Errors;

class ErrorFactory
{
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
            501 => new NotImplementedError($message),
            502 => new NetworkError($message),
            default => new AntdError($code, $message),
        };
    }
}
