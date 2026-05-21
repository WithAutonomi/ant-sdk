// Example 07: External-signer flow — public file + single-chunk publish.
//
// PR #90 added prepareUploadPublic / finalizeUpload and prepareChunkUpload /
// finalizeChunkUpload so the wallet key never has to live in the antd daemon.
// This example uses anvil deterministic account #0 as the external signer
// and exercises both round-trips end-to-end.
//
// See docs/external-signer-flow.md for the full reference; the IPaymentVault
// function selector and tuple ABI are baked into the ContractAbi declaration
// below.
//
// Requires web3dart (added as a dev_dependency).

import 'dart:io';
import 'dart:typed_data';

import 'package:antd/antd.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;

// Anvil deterministic account #0. Pre-funded with ETH (gas) and antToken
// (storage payment) by `ant dev start --enable-evm` devnet genesis. Never
// use this key anywhere except a throw-away local devnet.
const anvilKeyHex =
    'ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';

final BigInt maxUint256 = (BigInt.one << 256) - BigInt.one;

// IPaymentVault.payForQuotes((address rewardsAddress, uint256 amount, bytes32 quoteHash)[])
// Selector: 0xb6c2141b. See docs/external-signer-flow.md.
final paymentVaultAbiJson = '''[{
  "name": "payForQuotes",
  "type": "function",
  "stateMutability": "nonpayable",
  "inputs": [{
    "name": "payments",
    "type": "tuple[]",
    "components": [
      {"name": "rewardsAddress", "type": "address"},
      {"name": "amount", "type": "uint256"},
      {"name": "quoteHash", "type": "bytes32"}
    ]
  }],
  "outputs": []
}]''';

// Minimal ERC-20 ABI for approve(). antToken is a standard ERC-20.
//
// Output entry has an explicit "name" — web3dart's ContractAbi.fromJson
// throws "type 'Null' is not a subtype of type 'String'" if name is absent.
final erc20AbiJson = '''[{
  "name": "approve",
  "type": "function",
  "stateMutability": "nonpayable",
  "inputs": [
    {"name": "spender", "type": "address"},
    {"name": "value", "type": "uint256"}
  ],
  "outputs": [{"name": "success", "type": "bool"}]
}]''';

Future<void> main() async {
  final client = AntdClient();
  final credentials = EthPrivateKey.fromHex(anvilKeyHex);
  final tmp = await Directory.systemTemp.createTemp('antd-dart-07-extsig-');

  try {
    // --- 1. file upload via external signer ---------------------
    final fileContent =
        Uint8List.fromList(('hello external signer from dart (file)\n' * 16)
            .codeUnits);
    final src = File('${tmp.path}/file.bin');
    await src.writeAsBytes(fileContent);

    final filePrep = await client.prepareUploadPublic(src.path);
    print('File prepare: upload_id=${filePrep.uploadId.substring(0, 16)}..., '
        'payment_type=${filePrep.paymentType}, '
        'payments=${filePrep.payments.length}, total_amount=${filePrep.totalAmount}');

    final fileTxHashes = await externalSignerPay(
      filePrep.rpcUrl,
      filePrep.paymentVaultAddress,
      filePrep.paymentTokenAddress,
      filePrep.payments,
      credentials,
    );
    final fileFin = await client.finalizeUpload(filePrep.uploadId, fileTxHashes);
    print('File finalize: data_map_address=${fileFin.dataMapAddress}, '
        'chunks_stored=${fileFin.chunksStored}');

    final dst = File('${tmp.path}/file.bin.downloaded');
    await client.fileGetPublic(fileFin.dataMapAddress, dst.path);
    final got = await dst.readAsBytes();
    if (!_bytesEqual(got, fileContent)) {
      throw 'file round-trip mismatch';
    }
    print('File round-trip OK!');

    // --- 2. single-chunk publish via external signer ------------
    final chunkData = Uint8List.fromList(
        ('hello external signer from dart (chunk)\n' * 8).codeUnits);
    final chunkPrep = await client.prepareChunkUpload(chunkData);
    if (chunkPrep.alreadyStored) {
      print('Chunk prepare: already_stored, address=${chunkPrep.address}');
    } else {
      print('Chunk prepare: upload_id=${chunkPrep.uploadId.substring(0, 16)}..., '
          'address=${chunkPrep.address}, payments=${chunkPrep.payments.length}, '
          'total_amount=${chunkPrep.totalAmount}');
      final chunkTxHashes = await externalSignerPay(
        chunkPrep.rpcUrl,
        chunkPrep.paymentVaultAddress,
        chunkPrep.paymentTokenAddress,
        chunkPrep.payments,
        credentials,
      );
      final addr = await client.finalizeChunkUpload(chunkPrep.uploadId, chunkTxHashes);
      if (addr != chunkPrep.address) {
        throw 'chunk address mismatch: $addr != ${chunkPrep.address}';
      }
      print('Chunk finalize: address=$addr');
    }

    final chunkGot = await client.chunkGet(chunkPrep.address);
    if (!_bytesEqual(chunkGot, chunkData)) {
      throw 'chunk round-trip mismatch';
    }
    print('Chunk round-trip OK!');

    print('\n07_external_signer OK!');
  } finally {
    client.close();
    await tmp.delete(recursive: true);
  }
}

/// Run approve + payForQuotes on-chain for a daemon prepare response.
/// Returns the quote_hash -> tx_hash map the daemon's finalize_* methods
/// expect. Every entry maps to the same payForQuotes tx because every
/// quote in the wave is paid in one batched call.
Future<Map<String, String>> externalSignerPay(
  String rpcUrl,
  String vaultAddress,
  String tokenAddress,
  List<PaymentInfo> payments,
  EthPrivateKey credentials,
) async {
  // No on-chain work when every quoted chunk is already on-network.
  if (payments.isEmpty) return <String, String>{};

  final httpClient = http.Client();
  final web3 = Web3Client(rpcUrl, httpClient);
  try {
    final chainId = await web3.getChainId();

    // approve(vault, MAX) — idempotent and cheap; example uses MAX so
    // subsequent flows in this run skip a fresh approval.
    final tokenContract = DeployedContract(
      ContractAbi.fromJson(erc20AbiJson, 'IERC20'),
      EthereumAddress.fromHex(tokenAddress),
    );
    final approveFn = tokenContract.function('approve');
    final approveTxHash = await web3.sendTransaction(
      credentials,
      Transaction.callContract(
        contract: tokenContract,
        function: approveFn,
        parameters: [EthereumAddress.fromHex(vaultAddress), maxUint256],
        maxGas: 500000,
      ),
      chainId: chainId.toInt(),
    );
    final approveRcpt = await _waitReceipt(web3, approveTxHash);
    if (approveRcpt.status != true) {
      throw 'approve reverted: $approveTxHash';
    }

    // payForQuotes — one tx covering every quote in this wave.
    final vaultContract = DeployedContract(
      ContractAbi.fromJson(paymentVaultAbiJson, 'IPaymentVault'),
      EthereumAddress.fromHex(vaultAddress),
    );
    final payFn = vaultContract.function('payForQuotes');
    final tuples = payments.map((p) {
      final qhHex =
          p.quoteHash.startsWith('0x') ? p.quoteHash.substring(2) : p.quoteHash;
      return [
        EthereumAddress.fromHex(p.rewardsAddress),
        BigInt.parse(p.amount),
        _hexToBytes(qhHex),
      ];
    }).toList();

    final payTxHash = await web3.sendTransaction(
      credentials,
      Transaction.callContract(
        contract: vaultContract,
        function: payFn,
        parameters: [tuples],
        maxGas: 1000000,
      ),
      chainId: chainId.toInt(),
    );
    final payRcpt = await _waitReceipt(web3, payTxHash);
    if (payRcpt.status != true) {
      throw 'payForQuotes reverted: $payTxHash';
    }

    // Every quote in this wave was paid in the same call.
    return {for (final p in payments) p.quoteHash: payTxHash};
  } finally {
    web3.dispose();
    httpClient.close();
  }
}

Future<TransactionReceipt> _waitReceipt(Web3Client web3, String txHash) async {
  // Anvil instant-mines, so polling resolves within ~100 ms.
  for (var i = 0; i < 600; i++) {
    final rcpt = await web3.getTransactionReceipt(txHash);
    if (rcpt != null) return rcpt;
    await Future.delayed(const Duration(milliseconds: 100));
  }
  throw 'tx receipt timeout: $txHash';
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
