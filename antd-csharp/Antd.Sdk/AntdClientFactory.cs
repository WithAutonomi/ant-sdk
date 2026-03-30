namespace Antd.Sdk;

public static class AntdClient
{
    public static IAntdClient CreateRest(string baseUrl = "http://localhost:8082", TimeSpan? timeout = null)
        => new AntdRestClient(baseUrl, timeout);

    public static IAntdClient CreateGrpc(string target = "http://localhost:50051")
        => new AntdGrpcClient(target);

    public static IAntdClient Create(string transport = "rest", string? endpoint = null)
    {
        return transport.ToLowerInvariant() switch
        {
            "rest" => CreateRest(endpoint ?? "http://localhost:8082"),
            "grpc" => CreateGrpc(endpoint ?? "http://localhost:50051"),
            _ => throw new ArgumentException($"Unknown transport: {transport}. Use 'rest' or 'grpc'."),
        };
    }
}
