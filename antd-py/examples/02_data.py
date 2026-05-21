"""Example 02: Store and retrieve public data, with cost estimation.

Prerequisite: antd daemon running on local testnet.
"""

from antd import AntdClient

client = AntdClient()

# Estimate cost before storing
payload = b"Hello, Autonomi network!"
est = client.data_cost(payload)
print(
    f"Estimate: {est.file_size} bytes in {est.chunk_count} chunks, "
    f"storage {est.cost} atto, gas {est.estimated_gas_cost_wei} wei, "
    f"mode {est.payment_mode}"
)

# Store public data
result = client.data_put_public(payload)
print(f"Stored at address: {result.address}")
print(f"Chunks stored: {result.chunks_stored}, payment mode: {result.payment_mode_used}")

# Retrieve it back
data = client.data_get_public(result.address)
print(f"Retrieved: {data.decode()}")

assert data == payload, "Round-trip mismatch!"
print("Public data round-trip OK!")
