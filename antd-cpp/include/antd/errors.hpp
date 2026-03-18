#pragma once

#include <stdexcept>
#include <string>

namespace antd {

/// Base error type for all antd errors.
class AntdError : public std::runtime_error {
public:
    int status_code;

    AntdError(int status_code, const std::string& message)
        : std::runtime_error("antd error " + std::to_string(status_code) + ": " + message),
          status_code(status_code) {}
};

/// Invalid request parameters (HTTP 400).
class BadRequestError : public AntdError {
public:
    BadRequestError(const std::string& msg) : AntdError(400, msg) {}
};

/// Insufficient funds or payment failure (HTTP 402).
class PaymentError : public AntdError {
public:
    PaymentError(const std::string& msg) : AntdError(402, msg) {}
};

/// Resource not found on the network (HTTP 404).
class NotFoundError : public AntdError {
public:
    NotFoundError(const std::string& msg) : AntdError(404, msg) {}
};

/// Resource already exists (HTTP 409).
class AlreadyExistsError : public AntdError {
public:
    AlreadyExistsError(const std::string& msg) : AntdError(409, msg) {}
};

/// Version conflict or fork detected (HTTP 409).
class ForkError : public AntdError {
public:
    ForkError(const std::string& msg) : AntdError(409, msg) {}
};

/// Payload too large (HTTP 413).
class TooLargeError : public AntdError {
public:
    TooLargeError(const std::string& msg) : AntdError(413, msg) {}
};

/// Internal server error (HTTP 500).
class InternalError : public AntdError {
public:
    InternalError(const std::string& msg) : AntdError(500, msg) {}
};

/// Daemon cannot reach the network (HTTP 502).
class NetworkError : public AntdError {
public:
    NetworkError(const std::string& msg) : AntdError(502, msg) {}
};

/// Throw the appropriate AntdError subclass for an HTTP status code.
[[noreturn]] inline void error_for_status(int code, const std::string& message) {
    switch (code) {
        case 400: throw BadRequestError(message);
        case 402: throw PaymentError(message);
        case 404: throw NotFoundError(message);
        case 409: throw AlreadyExistsError(message);
        case 413: throw TooLargeError(message);
        case 500: throw InternalError(message);
        case 502: throw NetworkError(message);
        default:  throw AntdError(code, message);
    }
}

}  // namespace antd
