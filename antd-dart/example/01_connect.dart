import 'package:antd/antd.dart';

/// Demonstrates connecting to the antd daemon and checking health.
void main() async {
  final client = AntdClient();

  try {
    final health = await client.health();
    print('Daemon healthy: ${health.ok}');
    print('Network: ${health.network}');
  } on AntdError catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
