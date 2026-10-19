package com.autonomi.antd.errors;

import java.util.Map;

/**
 * Factory that maps HTTP status codes and daemon error codes to typed exceptions.
 */
public final class ExceptionFactory {

    private ExceptionFactory() {}

    /**
     * Creates the appropriate {@link AntdException} for a REST error response,
     * preferring the machine-readable {@code code} over the bare HTTP status
     * where they diverge: {@code PARTIAL_UPLOAD} arrives as a 502 that would
     * otherwise read as a generic {@link NetworkException}, so it becomes a
     * {@link PartialUploadException} carrying the body's counts and
     * {@code retryable} flag. Retention is known only when {@code retryable}
     * is a JSON boolean; a missing one (daemons older than 0.14.0), a
     * {@code null} or any other type reads as {@code retryable == false} with
     * retention unknown. The codes that share a status with older errors map
     * to their own types through {@link #fromPointerCode}: the 409s
     * {@code POINTER_FINAL}, {@code POINTER_FORKED} and {@code CONFLICT} (which
     * never read as {@link AlreadyExistsException}) and the 503
     * {@code CLOSE_GROUP_SHORTFALL}, whose {@code retryable} is {@code true}
     * only when the body carries the JSON boolean {@code true}. Every other
     * code keeps the status-based mapping of {@link #fromHttpStatus(int, String)}.
     *
     * <p>The body is input from the network, so this never throws on a
     * malformed one: only a {@code code} that is one of those JSON strings
     * selects a typed exception (a missing, null, numeric, object or array
     * {@code code}, or a body that was not a JSON object, keeps the
     * status-based mapping), a count that is not a JSON number reads as zero,
     * and a {@code retryable} that is not a JSON boolean reads as not
     * retryable (with retention unknown, for a partial upload).
     *
     * @param statusCode the HTTP status code
     * @param message    the error message from the daemon
     * @param body       the parsed JSON error body, or {@code null} when the
     *                   response was not JSON
     * @return a typed exception
     */
    public static AntdException fromErrorBody(int statusCode, String message, Map<String, Object> body) {
        if (body == null) {
            return fromHttpStatus(statusCode, message);
        }
        Object code = body.get("code");
        Object flag = body.get("retryable");
        if (PartialUploadException.CODE.equals(code)) {
            return new PartialUploadException(
                    message,
                    count(body, "chunks_stored"),
                    count(body, "chunks_failed"),
                    count(body, "total_chunks"),
                    flag instanceof Boolean b && b,
                    flag instanceof Boolean);
        }
        if (code instanceof String s) {
            AntdException typed = fromPointerCode(s, message, flag instanceof Boolean b && b);
            if (typed != null) return typed;
        }
        return fromHttpStatus(statusCode, message);
    }

    /**
     * Maps the daemon codes that share a status with older errors onto their
     * own types, or returns {@code null} for any other code. The REST clients
     * read the code from the error body; the gRPC client from the
     * {@code x-antd-error-code} trailer, once it has checked that the tag
     * agrees with the gRPC status code.
     *
     * @param code      the daemon's machine-readable error code
     * @param message   the error message from the daemon
     * @param retryable for {@code CLOSE_GROUP_SHORTFALL}: whether the daemon
     *                  kept a paid pointer finalize; ignored otherwise
     * @return the typed exception, or {@code null} when {@code code} is not one
     *         of {@code POINTER_FINAL}, {@code POINTER_FORKED}, {@code CONFLICT}
     *         or {@code CLOSE_GROUP_SHORTFALL}
     */
    public static AntdException fromPointerCode(String code, String message, boolean retryable) {
        if (code == null) return null;
        return switch (code) {
            case PointerFinalException.CODE -> new PointerFinalException(message);
            case ForkException.POINTER_FORKED_CODE -> new ForkException(message);
            case ConflictException.CODE -> new ConflictException(message);
            case CloseGroupShortfallException.CODE -> new CloseGroupShortfallException(message, retryable);
            default -> null;
        };
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
