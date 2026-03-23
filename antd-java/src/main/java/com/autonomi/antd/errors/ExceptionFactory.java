package com.autonomi.antd.errors;

/**
 * Factory that maps HTTP status codes to typed exceptions.
 */
public final class ExceptionFactory {

    private ExceptionFactory() {}

    /**
     * Creates the appropriate {@link AntdException} subclass for the given HTTP status code.
     *
     * @param statusCode the HTTP status code
     * @param message    the error message from the daemon
     * @return a typed exception
     */
    public static AntdException fromHttpStatus(int statusCode, String message) {
        return switch (statusCode) {
            case 400 -> new BadRequestException(message);
            case 402 -> new PaymentException(message);
            case 404 -> new NotFoundException(message);
            case 409 -> new AlreadyExistsException(message);
            case 413 -> new TooLargeException(message);
            case 500 -> new InternalException(message);
            case 501 -> new NotImplementedByServerException(message);
            case 502 -> new NetworkException(message);
            default -> new AntdException(statusCode, message);
        };
    }
}
