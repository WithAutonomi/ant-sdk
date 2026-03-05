"""Example 08: Register create, read, and update.

Registers store a single 32-byte hex value, owned by a keypair.
Updates are paid operations.
"""

import os

from antd import AntdClient

client = AntdClient()

# Generate a random secret key
secret_key = os.urandom(32).hex()

# Create a register with an initial value
initial_value = "00" * 32  # 32 zero bytes
result = client.register_create(secret_key, initial_value)
print(f"Register created at: {result.address}")
print(f"Cost: {result.cost} atto tokens")

# Read the register
reg = client.register_get(result.address)
print(f"Current value: {reg.value}")

# Update the register
new_value = os.urandom(32).hex()
update_result = client.register_update(secret_key, new_value)
print(f"Update cost: {update_result.cost} atto tokens")

# Read again to verify
reg = client.register_get(result.address)
print(f"Updated value: {reg.value}")

print("Register CRUD OK!")
