"""Example 08: Talk to the antd daemon over gRPC instead of REST.

The daemon listens for gRPC on a separate port (default :50051). The shape
mirrors the REST examples — health, then a chunk round-trip — but routed
through ``AntdClient(transport="grpc")`` instead of the default REST client.

Prerequisite: antd daemon running locally with gRPC enabled.
"""

from antd import AntdClient

client = AntdClient(transport="grpc")
print("Connected via gRPC")

status = client.health()
print(f"Daemon healthy: {status.ok}")
print(f"Network: {status.network}")

if not status.ok:
    print("ERROR: antd daemon is not healthy")
    raise SystemExit(1)

raw_data = b"Raw chunk content stored over gRPC"
result = client.chunk_put(raw_data)
print(f"Chunk stored at: {result.address}")

retrieved = client.chunk_get(result.address)
assert retrieved == raw_data, "Chunk round-trip mismatch over gRPC!"
print(f"Retrieved {len(retrieved)} bytes — gRPC round-trip OK!")

client.close()
