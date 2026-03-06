import Foundation

/// Base error for all Autonomi SDK operations.
public class AntdError: Error, CustomStringConvertible {
    public let message: String
    public let statusCode: Int

    public init(_ message: String, statusCode: Int = 0) {
        self.message = message
        self.statusCode = statusCode
    }

    public var description: String { "AntdError(\(statusCode)): \(message)" }
}

public final class NotFoundError: AntdError {
    public init(_ message: String, statusCode: Int = 404) {
        super.init(message, statusCode: statusCode)
    }
}

public final class AlreadyExistsError: AntdError {
    public init(_ message: String, statusCode: Int = 409) {
        super.init(message, statusCode: statusCode)
    }
}

public final class ForkError: AntdError {
    public init(_ message: String, statusCode: Int = 409) {
        super.init(message, statusCode: statusCode)
    }
}

public final class BadRequestError: AntdError {
    public init(_ message: String, statusCode: Int = 400) {
        super.init(message, statusCode: statusCode)
    }
}

public final class PaymentError: AntdError {
    public init(_ message: String, statusCode: Int = 402) {
        super.init(message, statusCode: statusCode)
    }
}

public final class NetworkError: AntdError {
    public init(_ message: String, statusCode: Int = 502) {
        super.init(message, statusCode: statusCode)
    }
}

public final class TooLargeError: AntdError {
    public init(_ message: String, statusCode: Int = 413) {
        super.init(message, statusCode: statusCode)
    }
}

public final class InternalError: AntdError {
    public init(_ message: String, statusCode: Int = 500) {
        super.init(message, statusCode: statusCode)
    }
}

enum ErrorMapping {

    static func fromHTTPStatus(_ statusCode: Int, body: String) -> AntdError {
        switch statusCode {
        case 400: return BadRequestError(body, statusCode: statusCode)
        case 402: return PaymentError(body, statusCode: statusCode)
        case 404: return NotFoundError(body, statusCode: statusCode)
        case 409: return AlreadyExistsError(body, statusCode: statusCode)
        case 413: return TooLargeError(body, statusCode: statusCode)
        case 500: return InternalError(body, statusCode: statusCode)
        case 502: return NetworkError(body, statusCode: statusCode)
        default: return AntdError(body, statusCode: statusCode)
        }
    }

    static func fromGRPCStatus(code: Int, detail: String) -> AntdError {
        // gRPC status codes: 5=NOT_FOUND, 6=ALREADY_EXISTS, 10=ABORTED,
        // 3=INVALID_ARGUMENT, 9=FAILED_PRECONDITION, 14=UNAVAILABLE,
        // 8=RESOURCE_EXHAUSTED, 13=INTERNAL
        switch code {
        case 5: return NotFoundError(detail)
        case 6: return AlreadyExistsError(detail)
        case 10: return ForkError(detail)
        case 3: return BadRequestError(detail)
        case 9: return PaymentError(detail)
        case 14: return NetworkError(detail)
        case 8: return TooLargeError(detail)
        case 13: return InternalError(detail)
        default: return AntdError(detail, statusCode: code)
        }
    }
}
