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

/** Payload too large (HTTP 413). */
export class TooLargeError extends AntdError {
  constructor(message: string, statusCode: number = 413) {
    super(message, statusCode);
    this.name = "TooLargeError";
  }
}

/** Internal server error (HTTP 500). */
export class InternalError extends AntdError {
  constructor(message: string, statusCode: number = 500) {
    super(message, statusCode);
    this.name = "InternalError";
  }
}

/** Not implemented (HTTP 501). */
export class NotImplementedError extends AntdError {
  constructor(message: string, statusCode: number = 501) {
    super(message, statusCode);
    this.name = "NotImplementedError";
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
  501: NotImplementedError,
  502: NetworkError,
};

/** Raise the appropriate AntdError subclass for an HTTP status code. */
export function fromHttpStatus(statusCode: number, message: string): AntdError {
  const ErrorClass = HTTP_STATUS_MAP[statusCode] ?? AntdError;
  return new ErrorClass(message, statusCode);
}
