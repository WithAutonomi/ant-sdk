import 'dart:convert';
import 'dart:typed_data';

import 'package:antd/antd.dart';

/// Demonstrates storing and retrieving public immutable data.
void main() async {
  final client = AntdClient();

  try {
    // Store data
    final data = Uint8List.fromList(utf8.encode('Hello, Autonomi!'));
    final result = await client.dataPutPublic(data);
    print('Stored at ${result.address} (cost: ${result.cost} atto)');

    // Retrieve data
    final retrieved = await client.dataGetPublic(result.address);
    print('Retrieved: ${utf8.decode(retrieved)}');

    // Estimate cost
    final cost = await client.dataCost(data);
    print('Estimated cost: $cost atto');
  } on AntdError catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
