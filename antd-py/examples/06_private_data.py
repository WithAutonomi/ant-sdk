"""Example 06: Private (encrypted) data round-trip.

Private data is encrypted before storage. The returned data map
is required to retrieve and decrypt the data.
"""

from antd import AntdClient

client = AntdClient()

# Store private data
secret_message = b"This message is encrypted on the network"
result = client.data_put(secret_message)
data_map = result.data_map
print(f"Data map: {data_map}")
print(f"Chunks stored: {result.chunks_stored}, payment mode: {result.payment_mode_used}")

# Retrieve and decrypt
retrieved = client.data_get(data_map)
print(f"Decrypted: {retrieved.decode()}")

assert retrieved == secret_message, "Private data round-trip mismatch!"
print("Private data round-trip OK!")
