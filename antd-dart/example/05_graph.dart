import 'package:antd/antd.dart';

/// Demonstrates graph entry (DAG node) operations.
void main() async {
  final client = AntdClient();

  try {
    // Create a graph entry
    final result = await client.graphEntryPut(
      'your_secret_key_hex',
      [], // no parents (root node)
      'content_hash_hex',
      [
        GraphDescendant(publicKey: 'descendant_pk_hex', content: 'desc_content_hex'),
      ],
    );
    print('Graph entry created at ${result.address} (cost: ${result.cost} atto)');

    // Read the graph entry
    final entry = await client.graphEntryGet(result.address);
    print('Owner: ${entry.owner}');
    print('Parents: ${entry.parents}');
    print('Content: ${entry.content}');
    print('Descendants: ${entry.descendants.length}');

    // Check existence
    final exists = await client.graphEntryExists(result.address);
    print('Exists: $exists');

    // Estimate cost
    final cost = await client.graphEntryCost('your_public_key_hex');
    print('Estimated cost: $cost atto');
  } on AntdError catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
