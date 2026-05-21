import 'dart:convert';
import 'dart:typed_data';

import 'package:antd/antd.dart';

/// Demonstrates storing and retrieving private (encrypted) data.
void main() async {
  final client = AntdClient();

  try {
    // Store private data — daemon returns the DataMap; caller keeps it.
    final data = Uint8List.fromList(utf8.encode('my secret data'));
    final result = await client.dataPut(data);
    print('Private data stored');
    print('  chunks: ${result.chunksStored}, mode: ${result.paymentModeUsed}');
    print('  data map: ${result.dataMap}');

    // Retrieve private data using the data map
    final retrieved = await client.dataGet(result.dataMap);
    print('Retrieved: ${utf8.decode(retrieved)}');
  } on AntdError catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
