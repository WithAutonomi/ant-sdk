using System.Net;
using Grpc.Core;

namespace Antd.Sdk;

public class AntdException : Exception
{
    public int StatusCode { get; }

    public AntdException(string message, int statusCode = 0)
        : base(message) => StatusCode = statusCode;
}

public class NotFoundException : AntdException
{
    public NotFoundException(string message, int statusCode = 404)
        : base(message, statusCode) { }
}

public class AlreadyExistsException : AntdException
{
    public AlreadyExistsException(string message, int statusCode = 409)
        : base(message, statusCode) { }
}

public class ForkException : AntdException
{
    public ForkException(string message, int statusCode = 409)
        : base(message, statusCode) { }
}

public class BadRequestException : AntdException
{
    public BadRequestException(string message, int statusCode = 400)
        : base(message, statusCode) { }
}

public class PaymentException : AntdException
{
    public PaymentException(string message, int statusCode = 402)
        : base(message, statusCode) { }
}

public class NetworkException : AntdException
{
    public NetworkException(string message, int statusCode = 502)
        : base(message, statusCode) { }
}

public class TooLargeException : AntdException
{
    public TooLargeException(string message, int statusCode = 413)
        : base(message, statusCode) { }
}

public class InternalException : AntdException
{
    public InternalException(string message, int statusCode = 500)
        : base(message, statusCode) { }
}

public class NotImplementedByServerException : AntdException
{
    public NotImplementedByServerException(string message, int statusCode = 501)
        : base(message, statusCode) { }
}

internal static class ExceptionMapping
{
    public static AntdException FromHttpStatus(HttpStatusCode status, string body)
    {
        var code = (int)status;
        return code switch
        {
            400 => new BadRequestException(body, code),
            402 => new PaymentException(body, code),
            404 => new NotFoundException(body, code),
            409 => new AlreadyExistsException(body, code),
            413 => new TooLargeException(body, code),
            500 => new InternalException(body, code),
            501 => new NotImplementedByServerException(body, code),
            502 => new NetworkException(body, code),
            _ => new AntdException(body, code),
        };
    }

    public static AntdException FromGrpcStatus(RpcException ex)
    {
        var detail = ex.Status.Detail;
        return ex.StatusCode switch
        {
            Grpc.Core.StatusCode.NotFound => new NotFoundException(detail),
            Grpc.Core.StatusCode.AlreadyExists => new AlreadyExistsException(detail),
            Grpc.Core.StatusCode.Aborted => new ForkException(detail),
            Grpc.Core.StatusCode.InvalidArgument => new BadRequestException(detail),
            Grpc.Core.StatusCode.FailedPrecondition => new PaymentException(detail),
            Grpc.Core.StatusCode.Unavailable => new NetworkException(detail),
            Grpc.Core.StatusCode.ResourceExhausted => new TooLargeException(detail),
            Grpc.Core.StatusCode.Internal => new InternalException(detail),
            _ => new AntdException(detail, (int)ex.StatusCode),
        };
    }
}
