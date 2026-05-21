import 'dart:io';
import 'package:antd/antd.dart';

/// Demonstrates file upload/download with a real tempfile + round-trip assertion.
Future<void> main() async {
  final client = AntdClient();
  final tmp = await Directory.systemTemp.createTemp('antd-dart-04-files-');

  try {
    const fileContent = 'Hello from a file on Autonomi!';
    final srcFile = File('${tmp.path}/hello.txt');
    await srcFile.writeAsString(fileContent);

    final cost = await client.fileCost(srcFile.path);
    print('Estimated cost: ${cost.cost} atto across ${cost.chunkCount} chunks');

    final result = await client.filePutPublic(srcFile.path);
    print('File uploaded at ${result.address}');
    print('  storage: ${result.storageCostAtto} atto, gas: ${result.gasCostWei} wei');
    print('  chunks: ${result.chunksStored}, mode: ${result.paymentModeUsed}');

    final dstFile = File('${tmp.path}/hello.txt.downloaded');
    await client.fileGetPublic(result.address, dstFile.path);
    print('File downloaded to ${dstFile.path}');

    final got = await dstFile.readAsString();
    if (got != fileContent) {
      stderr.writeln('round-trip mismatch on hello.txt');
      exitCode = 1;
      return;
    }

    print('File upload/download OK!');
  } finally {
    client.close();
    await tmp.delete(recursive: true);
  }
}
