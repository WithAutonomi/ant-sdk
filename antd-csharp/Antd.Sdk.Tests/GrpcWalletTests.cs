using Antd.V1;
using Grpc.Core;
using Grpc.Core.Testing;
using Xunit;

namespace Antd.Sdk.Tests;

/// <summary>
/// V2-286 WalletService wire-mapping tests for AntdGrpcClient. Bypasses the
/// real GrpcChannel by injecting a WalletService.WalletServiceClient subclass
/// that overrides the generated *Async methods to return canned
/// <see cref="AsyncUnaryCall{TResponse}"/> values via the
/// <see cref="TestCalls"/> helpers. Mirrors the antd-rust / antd-go /
/// antd-py / antd-java / antd-kotlin suites.
/// </summary>
public sealed class GrpcWalletTests
{
    private static AsyncUnaryCall<T> Reply<T>(T value) =>
        TestCalls.AsyncUnaryCall(
            Task.FromResult(value),
            Task.FromResult(new Metadata()),
            () => Status.DefaultSuccess,
            () => new Metadata(),
            () => { });

    private static AsyncUnaryCall<T> Failure<T>(StatusCode code, string detail) =>
        TestCalls.AsyncUnaryCall(
            Task.FromException<T>(new RpcException(new Status(code, detail))),
            Task.FromResult(new Metadata()),
            () => new Status(code, detail),
            () => new Metadata(),
            () => { });

    private sealed class MockWalletServiceClient : WalletService.WalletServiceClient
    {
        public override AsyncUnaryCall<GetWalletAddressResponse> GetAddressAsync(
            GetWalletAddressRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
            => Reply(new GetWalletAddressResponse
            {
                Address = "0xabc1234567890abcdef1234567890abcdef123456",
            });

        public override AsyncUnaryCall<GetWalletBalanceResponse> GetBalanceAsync(
            GetWalletBalanceRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
            => Reply(new GetWalletBalanceResponse
            {
                Balance = "1000000000000000000",
                GasBalance = "500000000000000000",
            });

        public override AsyncUnaryCall<WalletApproveResponse> ApproveAsync(
            WalletApproveRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
            => Reply(new WalletApproveResponse { Approved = true });
    }

    private sealed class UnconfiguredWalletServiceClient : WalletService.WalletServiceClient
    {
        public override AsyncUnaryCall<GetWalletAddressResponse> GetAddressAsync(
            GetWalletAddressRequest request, Metadata? headers = null,
            DateTime? deadline = null, CancellationToken cancellationToken = default)
            => Failure<GetWalletAddressResponse>(
                StatusCode.FailedPrecondition,
                "wallet not configured — set AUTONOMI_WALLET_KEY");
    }

    private sealed class TestServiceInvoker : CallInvoker
    {
        public override TResponse BlockingUnaryCall<TRequest, TResponse>(
            Method<TRequest, TResponse> method, string? host, CallOptions options, TRequest request) =>
            throw new NotSupportedException("test invoker — not exercised");
        public override AsyncUnaryCall<TResponse> AsyncUnaryCall<TRequest, TResponse>(
            Method<TRequest, TResponse> method, string? host, CallOptions options, TRequest request) =>
            throw new NotSupportedException("test invoker — not exercised");
        public override AsyncServerStreamingCall<TResponse> AsyncServerStreamingCall<TRequest, TResponse>(
            Method<TRequest, TResponse> method, string? host, CallOptions options, TRequest request) =>
            throw new NotSupportedException("test invoker — not exercised");
        public override AsyncClientStreamingCall<TRequest, TResponse> AsyncClientStreamingCall<TRequest, TResponse>(
            Method<TRequest, TResponse> method, string? host, CallOptions options) =>
            throw new NotSupportedException("test invoker — not exercised");
        public override AsyncDuplexStreamingCall<TRequest, TResponse> AsyncDuplexStreamingCall<TRequest, TResponse>(
            Method<TRequest, TResponse> method, string? host, CallOptions options) =>
            throw new NotSupportedException("test invoker — not exercised");
    }

    private static AntdGrpcClient MakeClient(WalletService.WalletServiceClient wallet) =>
        new AntdGrpcClient(
            health: new HealthService.HealthServiceClient(new TestServiceInvoker()),
            data: new DataService.DataServiceClient(new TestServiceInvoker()),
            chunks: new ChunkService.ChunkServiceClient(new TestServiceInvoker()),
            files: new FileService.FileServiceClient(new TestServiceInvoker()),
            wallet: wallet);

    [Fact]
    public async Task WalletAddress_ReturnsAddress()
    {
        var client = MakeClient(new MockWalletServiceClient());
        var r = await client.WalletAddressAsync();
        Assert.Equal("0xabc1234567890abcdef1234567890abcdef123456", r.Address);
    }

    [Fact]
    public async Task WalletBalance_ReturnsBalances()
    {
        var client = MakeClient(new MockWalletServiceClient());
        var r = await client.WalletBalanceAsync();
        Assert.Equal("1000000000000000000", r.Balance);
        Assert.Equal("500000000000000000", r.GasBalance);
    }

    [Fact]
    public async Task WalletApprove_ReturnsTrue()
    {
        var client = MakeClient(new MockWalletServiceClient());
        Assert.True(await client.WalletApproveAsync());
    }

    /// <summary>
    /// Daemon emits gRPC FailedPrecondition for "wallet not configured"; the
    /// established mapping (ExceptionMapping.FromGrpcStatus / Wrap()) surfaces
    /// this as PaymentException. (Semantic a bit off vs REST's 503 but matches
    /// every SDK.)
    /// </summary>
    [Fact]
    public async Task WalletAddress_Unconfigured_ThrowsPaymentException()
    {
        var client = MakeClient(new UnconfiguredWalletServiceClient());
        var ex = await Assert.ThrowsAsync<PaymentException>(() => client.WalletAddressAsync());
        Assert.Contains("wallet not configured", ex.Message);
    }
}
