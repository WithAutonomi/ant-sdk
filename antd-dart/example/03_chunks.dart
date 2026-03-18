import 'dart:convert';
import 'dart:typed_data';

import 'package:antd/antd.dart';

/// Demonstrates storing and retrieving raw chunks.
void main() async {
  final client = AntdClient();

  try {
    // Store a chunk
    final data = Uint8List.fromList(utf8.encode('raw chunk data'));
    final result = await client.chunkPut(data);
    print('Chunk stored at ${result.address} (cost: ${result.cost} atto)');

    // Retrieve the chunk
    final retrieved = await client.chunkGet(result.address);
    print('Retrieved: ${utf8.decode(retrieved)}');
  } on AntdError catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
