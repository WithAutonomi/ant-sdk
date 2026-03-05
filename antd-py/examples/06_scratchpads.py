"""Example 06: Create, read, and update versioned scratchpads.

Scratchpads are versioned mutable storage with a content type field.
They are owned by a keypair and have a monotonic counter.
"""

import os

from antd import AntdClient

client = AntdClient()

# Generate a random secret key
secret_key = os.urandom(32).hex()

# Create a scratchpad with initial data
initial_data = b"scratchpad v1 data"
content_type = 1  # application-defined encoding
result = client.scratchpad_create(secret_key, content_type, initial_data)
print(f"Scratchpad created at: {result.address}")
print(f"Cost: {result.cost} atto tokens")

# Read the scratchpad
pad = client.scratchpad_get(result.address)
print(f"Data encoding: {pad.data_encoding}")
print(f"Counter: {pad.counter}")
print(f"Data length: {len(pad.data)} bytes")

# Check existence
exists = client.scratchpad_exists(result.address)
print(f"Scratchpad exists: {exists}")

# Update scratchpad with new data
updated_data = b"scratchpad v2 data"
client.scratchpad_update(secret_key, content_type, updated_data)
print("Scratchpad updated")

# Read again to verify
pad = client.scratchpad_get(result.address)
print(f"Counter after update: {pad.counter}")

print("Scratchpad CRUD OK!")
