"""Example 06: Private (encrypted) data round-trip.

Private data is encrypted before storage. The returned data map
is required to retrieve and decrypt the data.
"""

from antd import AntdClient

client = AntdClient()

# Store private data
secret_message = b"This message is encrypted on the network"
result = client.data_put_private(secret_message)
data_map = result.address  # for private data, address holds the data map
print(f"Data map: {data_map}")
print(f"Cost: {result.cost} atto tokens")

# Retrieve and decrypt
retrieved = client.data_get_private(data_map)
print(f"Decrypted: {retrieved.decode()}")

assert retrieved == secret_message, "Private data round-trip mismatch!"
print("Private data round-trip OK!")
