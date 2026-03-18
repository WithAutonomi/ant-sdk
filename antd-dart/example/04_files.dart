import 'package:antd/antd.dart';

/// Demonstrates file and directory upload/download.
void main() async {
  final client = AntdClient();

  try {
    // Upload a file
    final result = await client.fileUploadPublic('/path/to/file.txt');
    print('File uploaded at ${result.address} (cost: ${result.cost} atto)');

    // Download a file
    await client.fileDownloadPublic(result.address, '/path/to/output.txt');
    print('File downloaded');

    // Upload a directory
    final dirResult = await client.dirUploadPublic('/path/to/directory');
    print('Directory uploaded at ${dirResult.address}');

    // Download a directory
    await client.dirDownloadPublic(dirResult.address, '/path/to/output-dir');
    print('Directory downloaded');

    // Estimate file upload cost
    final cost = await client.fileCost('/path/to/file.txt');
    print('Estimated cost: $cost atto');
  } on AntdError catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
