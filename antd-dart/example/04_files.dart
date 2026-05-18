import 'package:antd/antd.dart';

/// Demonstrates file upload/download.
void main() async {
  final client = AntdClient();

  try {
    // Upload a file
    final result = await client.fileUploadPublic('/path/to/file.txt');
    print('File uploaded at ${result.address}');
    print('  storage: ${result.storageCostAtto} atto, gas: ${result.gasCostWei} wei');
    print('  chunks: ${result.chunksStored}, mode: ${result.paymentModeUsed}');

    // Download a file
    await client.fileDownloadPublic(result.address, '/path/to/output.txt');
    print('File downloaded');

    // Estimate file upload cost
    final cost = await client.fileCost('/path/to/file.txt');
    print('Estimated cost: $cost atto');
  } on AntdError catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
