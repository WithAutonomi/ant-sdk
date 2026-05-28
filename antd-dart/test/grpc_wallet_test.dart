import 'package:antd/src/grpc_client.dart';
import 'package:antd/src/errors.dart';
import 'package:antd/src/generated/antd/v1/wallet.pb.dart' as wallet_msg;
import 'package:antd/src/generated/antd/v1/wallet.pbgrpc.dart' as wallet_pb;
import 'package:grpc/grpc.dart';
import 'package:test/test.dart';

/// V2-286 WalletService wire-mapping tests for [GrpcAntdClient].
///
/// Spins up a real grpc-dart server on `127.0.0.1:0` with a mock
/// WalletService implementation, then dials with a real [GrpcAntdClient].
/// Mirrors the antd-rust / antd-go / antd-py / antd-java / antd-kotlin /
/// antd-csharp / antd-ruby suites.
void main() {
  late Server server;
  late GrpcAntdClient client;

  Future<void> startServer(wallet_pb.WalletServiceBase service) async {
    server = Server.create(services: [service]);
    await server.serve(address: '127.0.0.1', port: 0);
    client = GrpcAntdClient(host: '127.0.0.1', port: server.port!);
  }

  tearDown(() async {
    await server.shutdown();
  });

  group('WalletService — happy path', () {
    setUp(() async {
      await startServer(_MockWalletService());
    });

    test('walletAddress returns address', () async {
      final r = await client.walletAddress();
      expect(r.address, equals('0xabc1234567890abcdef1234567890abcdef123456'));
    });

    test('walletBalance returns balances', () async {
      final r = await client.walletBalance();
      expect(r.balance, equals('1000000000000000000'));
      expect(r.gasBalance, equals('500000000000000000'));
    });

    test('walletApprove returns true', () async {
      expect(await client.walletApprove(), isTrue);
    });
  });

  group('WalletService — unconfigured', () {
    setUp(() async {
      await startServer(_UnconfiguredWalletService());
    });

    /// Daemon emits gRPC FailedPrecondition for "wallet not configured"; the
    /// established mapping (_handleError) surfaces this as PaymentError.
    /// (Semantic a bit off vs REST's 503 but matches every SDK.)
    test('walletAddress raises PaymentError', () async {
      await expectLater(
        client.walletAddress(),
        throwsA(isA<PaymentError>().having(
          (e) => e.toString(),
          'message contains wallet not configured',
          contains('wallet not configured'),
        )),
      );
    });
  });
}

class _MockWalletService extends wallet_pb.WalletServiceBase {
  @override
  Future<wallet_msg.GetWalletAddressResponse> getAddress(
      ServiceCall call, wallet_msg.GetWalletAddressRequest request) async {
    return wallet_msg.GetWalletAddressResponse()
      ..address = '0xabc1234567890abcdef1234567890abcdef123456';
  }

  @override
  Future<wallet_msg.GetWalletBalanceResponse> getBalance(
      ServiceCall call, wallet_msg.GetWalletBalanceRequest request) async {
    return wallet_msg.GetWalletBalanceResponse()
      ..balance = '1000000000000000000'
      ..gasBalance = '500000000000000000';
  }

  @override
  Future<wallet_msg.WalletApproveResponse> approve(
      ServiceCall call, wallet_msg.WalletApproveRequest request) async {
    return wallet_msg.WalletApproveResponse()..approved = true;
  }
}

class _UnconfiguredWalletService extends wallet_pb.WalletServiceBase {
  @override
  Future<wallet_msg.GetWalletAddressResponse> getAddress(
      ServiceCall call, wallet_msg.GetWalletAddressRequest request) async {
    throw GrpcError.failedPrecondition(
        'wallet not configured — set AUTONOMI_WALLET_KEY');
  }

  @override
  Future<wallet_msg.GetWalletBalanceResponse> getBalance(
      ServiceCall call, wallet_msg.GetWalletBalanceRequest request) async {
    throw GrpcError.failedPrecondition(
        'wallet not configured — set AUTONOMI_WALLET_KEY');
  }

  @override
  Future<wallet_msg.WalletApproveResponse> approve(
      ServiceCall call, wallet_msg.WalletApproveRequest request) async {
    throw GrpcError.failedPrecondition(
        'wallet not configured — set AUTONOMI_WALLET_KEY');
  }
}
