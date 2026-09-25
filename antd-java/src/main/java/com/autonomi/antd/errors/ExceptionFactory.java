package com.autonomi.antd.errors;

import java.util.Map;

/**
 * Factory that maps HTTP status codes to typed exceptions.
 */
public final class ExceptionFactory {

    private ExceptionFactory() {}

    /**
     * Creates the appropriate {@link AntdException} for a REST error response,
     * preferring the machine-readable {@code code} over the bare HTTP status
     * where they diverge: {@code PARTIAL_UPLOAD} arrives as a 502 that would
     * otherwise read as a generic {@link NetworkException}, so it becomes a
     * {@link PartialUploadException} carrying the body's counts and
     * {@code retryable} flag (absent on daemons older than 0.14.0, defaulting
     * to {@code false}). Every other code keeps the status-based mapping of
     * {@link #fromHttpStatus(int, String)}.
     *
     * <p>The body is input from the network, so this never throws on a
     * malformed one: only a {@code code} that is the JSON string
     * {@code "PARTIAL_UPLOAD"} selects the typed exception (a missing, null,
     * numeric, object or array {@code code}, or a body that was not a JSON
     * object, keeps the status-based mapping), and a count that is not a JSON
     * number or a {@code retryable} that is not a JSON boolean reads as zero /
     * {@code false}.
     *
     * @param statusCode the HTTP status code
     * @param message    the error message from the daemon
     * @param body       the parsed JSON error body, or {@code null} when the
     *                   response was not JSON
     * @return a typed exception
     */
    public static AntdException fromErrorBody(int statusCode, String message, Map<String, Object> body) {
        if (body != null && PartialUploadException.CODE.equals(body.get("code"))) {
            return new PartialUploadException(
                    message,
                    count(body, "chunks_stored"),
                    count(body, "chunks_failed"),
                    count(body, "total_chunks"),
                    body.get("retryable") instanceof Boolean b && b);
        }
        return fromHttpStatus(statusCode, message);
    }

    private static long count(Map<String, Object> body, String key) {
        Object v = body.get(key);
        return v instanceof Number n ? n.longValue() : 0L;
    }

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
            case 502 -> new NetworkException(message);
            case 503 -> new ServiceUnavailableException(message);
            default -> new AntdException(statusCode, message);
        };
    }
}
