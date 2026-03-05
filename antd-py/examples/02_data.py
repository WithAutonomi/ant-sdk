"""Example 02: Store and retrieve public data, with cost estimation.

Prerequisite: antd daemon running on local testnet.
"""

from antd import AntdClient

client = AntdClient()

# Estimate cost before storing
payload = b"Hello, Autonomi network!"
cost = client.data_cost(payload)
print(f"Estimated cost: {cost} atto tokens")

# Store public data
result = client.data_put_public(payload)
print(f"Stored at address: {result.address}")
print(f"Actual cost: {result.cost} atto tokens")

# Retrieve it back
data = client.data_get_public(result.address)
print(f"Retrieved: {data.decode()}")

assert data == payload, "Round-trip mismatch!"
print("Public data round-trip OK!")
