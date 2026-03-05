"""Example 03: Store and retrieve raw chunks.

Chunks are the lowest-level storage primitive on Autonomi.
"""

from antd import AntdClient

client = AntdClient()

# Store a raw chunk
raw_data = b"Raw chunk content for direct storage"
result = client.chunk_put(raw_data)
print(f"Chunk stored at: {result.address}")
print(f"Cost: {result.cost} atto tokens")

# Retrieve the chunk
retrieved = client.chunk_get(result.address)
print(f"Retrieved {len(retrieved)} bytes")

assert retrieved == raw_data, "Chunk round-trip mismatch!"
print("Chunk round-trip OK!")
