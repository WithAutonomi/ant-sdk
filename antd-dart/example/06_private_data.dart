import 'dart:convert';
import 'dart:typed_data';

import 'package:antd/antd.dart';

/// Demonstrates storing and retrieving private (encrypted) data.
void main() async {
  final client = AntdClient();

  try {
    // Store private data
    final data = Uint8List.fromList(utf8.encode('my secret data'));
    final result = await client.dataPutPrivate(data);
    print('Private data stored (cost: ${result.cost} atto)');
    print('Data map: ${result.address}');

    // Retrieve private data using the data map
    final retrieved = await client.dataGetPrivate(result.address);
    print('Retrieved: ${utf8.decode(retrieved)}');
  } on AntdError catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
