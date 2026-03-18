/// Error set for antd client operations.
pub const AntdError = error{
    BadRequest,
    Payment,
    NotFound,
    AlreadyExists,
    Fork,
    TooLarge,
    Internal,
    Network,
    UnexpectedStatus,
    HttpError,
    JsonError,
};

/// Carries HTTP status code and message alongside an AntdError.
pub const ErrorInfo = struct {
    status_code: u16,
    message: []const u8,
};

/// Maps an HTTP status code to the corresponding AntdError.
pub fn errorForStatus(code: u16) AntdError {
    return switch (code) {
        400 => error.BadRequest,
        402 => error.Payment,
        404 => error.NotFound,
        409 => error.AlreadyExists,
        413 => error.TooLarge,
        500 => error.Internal,
        502 => error.Network,
        else => error.UnexpectedStatus,
    };
}
