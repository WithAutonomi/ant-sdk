package com.autonomi.sdk

import io.grpc.StatusException
import io.grpc.StatusRuntimeException
import io.grpc.Status

open class AntdException(message: String, val statusCode: Int = 0) : Exception(message)

class NotFoundException(message: String, statusCode: Int = 404) : AntdException(message, statusCode)
class AlreadyExistsException(message: String, statusCode: Int = 409) : AntdException(message, statusCode)
class ForkException(message: String, statusCode: Int = 409) : AntdException(message, statusCode)
class BadRequestException(message: String, statusCode: Int = 400) : AntdException(message, statusCode)
class PaymentException(message: String, statusCode: Int = 402) : AntdException(message, statusCode)
class NetworkException(message: String, statusCode: Int = 502) : AntdException(message, statusCode)
class TooLargeException(message: String, statusCode: Int = 413) : AntdException(message, statusCode)
class InternalException(message: String, statusCode: Int = 500) : AntdException(message, statusCode)
class ServiceUnavailableException(message: String, statusCode: Int = 503) : AntdException(message, statusCode)

internal object ExceptionMapping {

    fun fromHttpStatus(statusCode: Int, body: String): AntdException = when (statusCode) {
        400 -> BadRequestException(body, statusCode)
        402 -> PaymentException(body, statusCode)
        404 -> NotFoundException(body, statusCode)
        409 -> AlreadyExistsException(body, statusCode)
        413 -> TooLargeException(body, statusCode)
        500 -> InternalException(body, statusCode)
        502 -> NetworkException(body, statusCode)
        503 -> ServiceUnavailableException(body, statusCode)
        else -> AntdException(body, statusCode)
    }

    fun fromGrpcStatus(ex: StatusRuntimeException): AntdException {
        val detail = ex.status.description ?: ex.message ?: "Unknown error"
        return when (ex.status.code) {
            Status.Code.NOT_FOUND -> NotFoundException(detail)
            Status.Code.ALREADY_EXISTS -> AlreadyExistsException(detail)
            Status.Code.ABORTED -> ForkException(detail)
            Status.Code.INVALID_ARGUMENT -> BadRequestException(detail)
            Status.Code.FAILED_PRECONDITION -> PaymentException(detail)
            Status.Code.UNAVAILABLE -> NetworkException(detail)
            Status.Code.RESOURCE_EXHAUSTED -> TooLargeException(detail)
            Status.Code.INTERNAL -> InternalException(detail)
            else -> AntdException(detail, ex.status.code.value())
        }
    }
}
