/** Base exception for all antd errors. */
export class AntdError extends Error {
  statusCode: number;

  constructor(message: string, statusCode: number = 0) {
    super(message);
    this.name = "AntdError";
    this.statusCode = statusCode;
  }
}

/** Resource not found (HTTP 404). */
export class NotFoundError extends AntdError {
  constructor(message: string, statusCode: number = 404) {
    super(message, statusCode);
    this.name = "NotFoundError";
  }
}

/** Resource already exists (HTTP 409). */
export class AlreadyExistsError extends AntdError {
  constructor(message: string, statusCode: number = 409) {
    super(message, statusCode);
    this.name = "AlreadyExistsError";
  }
}

/** Fork/version conflict detected (HTTP 409). */
export class ForkError extends AntdError {
  constructor(message: string, statusCode: number = 409) {
    super(message, statusCode);
    this.name = "ForkError";
  }
}

/** Invalid request (HTTP 400). */
export class BadRequestError extends AntdError {
  constructor(message: string, statusCode: number = 400) {
    super(message, statusCode);
    this.name = "BadRequestError";
  }
}

/** Payment or wallet error (HTTP 402). */
export class PaymentError extends AntdError {
  constructor(message: string, statusCode: number = 402) {
    super(message, statusCode);
    this.name = "PaymentError";
  }
}

/** Network communication error (HTTP 502). */
export class NetworkError extends AntdError {
  constructor(message: string, statusCode: number = 502) {
    super(message, statusCode);
    this.name = "NetworkError";
  }
}

/**
 * A finalize stored some chunks while others remained unstored after the
 * daemon's retries (HTTP 502 with `code: "PARTIAL_UPLOAD"`). The on-chain
 * payment persists and the stored chunks stay on the network. How to finish
 * the upload depends on `retryable`:
 *
 *   - `retryable === true`: the daemon kept the paid attempt (payment proofs
 *     + unstored chunks) under the same `upload_id`. Call the same finalize
 *     method again with the same arguments to store the remainder against the
 *     same payment — no re-prepare, no second signature, no double payment.
 *     Bound the loop: a persistent failure throws this error on every call,
 *     so cap the attempts and treat a `chunksFailed` that stops shrinking as
 *     stuck. The retained attempt expires with the daemon's pending-upload
 *     TTL. (antd >= 0.14.0; older daemons never send the flag, so `retryable`
 *     reads `false` and the re-prepare path applies.)
 *   - `retryable === false`: nothing was retained (a merkle finalize with
 *     deliberately unpaid batches, or an older daemon). Re-preparing the same
 *     content skips already-stored chunks, so a retry pays only for the
 *     missing remainder.
 *
 * Extends {@link NetworkError} because a 502 mapped to `NetworkError` before
 * the daemon exposed the structured code, so existing
 * `instanceof NetworkError` checks keep matching; test for this class first.
 * See `docs/external-signer-flow.md` §6.
 */
export class PartialUploadError extends NetworkError {
  /** Chunks the daemon stored before giving up. */
  chunksStored: number;
  /** Chunks still unstored after the daemon's retries. */
  chunksFailed: number;
  /** Chunks in the upload (stored + failed). */
  totalChunks: number;
  /** `true` when the paid attempt was retained for a same-`upload_id` retry. */
  retryable: boolean;

  constructor(
    message: string,
    fields: {
      chunksStored?: number;
      chunksFailed?: number;
      totalChunks?: number;
      retryable?: boolean;
    } = {},
    statusCode: number = 502,
  ) {
    super(message, statusCode);
    this.name = "PartialUploadError";
    this.chunksStored = fields.chunksStored ?? 0;
    this.chunksFailed = fields.chunksFailed ?? 0;
    this.totalChunks = fields.totalChunks ?? 0;
    this.retryable = fields.retryable ?? false;
  }
}

/** Payload too large (HTTP 413). */
export class TooLargeError extends AntdError {
  constructor(message: string, statusCode: number = 413) {
    super(message, statusCode);
    this.name = "TooLargeError";
  }
}

/** Service unavailable, e.g. wallet not configured (HTTP 503). */
export class ServiceUnavailableError extends AntdError {
  constructor(message: string, statusCode: number = 503) {
    super(message, statusCode);
    this.name = "ServiceUnavailableError";
  }
}

/** Internal server error (HTTP 500). */
export class InternalError extends AntdError {
  constructor(message: string, statusCode: number = 500) {
    super(message, statusCode);
    this.name = "InternalError";
  }
}

/** HTTP status code -> exception class mapping. */
const HTTP_STATUS_MAP: Record<number, new (message: string, statusCode: number) => AntdError> = {
  400: BadRequestError,
  402: PaymentError,
  404: NotFoundError,
  409: AlreadyExistsError,
  413: TooLargeError,
  500: InternalError,
  502: NetworkError,
  503: ServiceUnavailableError,
};

/** Raise the appropriate AntdError subclass for an HTTP status code. */
export function fromHttpStatus(statusCode: number, message: string): AntdError {
  const ErrorClass = HTTP_STATUS_MAP[statusCode] ?? AntdError;
  return new ErrorClass(message, statusCode);
}

/**
 * Build the AntdError for a REST error response, preferring the body's
 * machine-readable `code` over the bare HTTP status where they diverge.
 * `PARTIAL_UPLOAD` arrives as a 502 that would otherwise read as a plain
 * {@link NetworkError}; it becomes a {@link PartialUploadError} carrying the
 * body's `chunks_stored` / `chunks_failed` / `total_chunks` and `retryable`
 * (absent on antd < 0.14.0, so it defaults to `false`). Every other code
 * keeps the status-based mapping of {@link fromHttpStatus}. `body` may be
 * `undefined` when the response was not JSON.
 */
export function fromErrorBody(
  statusCode: number,
  message: string,
  body?: Record<string, unknown>,
): AntdError {
  if (body?.code === "PARTIAL_UPLOAD") {
    return new PartialUploadError(
      message,
      {
        chunksStored: typeof body.chunks_stored === "number" ? body.chunks_stored : 0,
        chunksFailed: typeof body.chunks_failed === "number" ? body.chunks_failed : 0,
        totalChunks: typeof body.total_chunks === "number" ? body.total_chunks : 0,
        retryable: body.retryable === true,
      },
      statusCode,
    );
  }
  return fromHttpStatus(statusCode, message);
}
