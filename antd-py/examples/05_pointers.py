"""Example 05: Create, read, and update mutable pointers.

Pointers are mutable references that point to other network objects.
They are owned by a keypair and can be updated by the owner.
"""

import os

from antd import AntdClient
from antd.models import PointerTarget

client = AntdClient()

# Generate a random secret key (in production, use a proper key)
secret_key = os.urandom(32).hex()

# Store some data to point to
data_v1 = client.data_put_public(b"version 1")
data_v2 = client.data_put_public(b"version 2")

# Create a pointer to v1
target_v1 = PointerTarget(kind="chunk", address=data_v1.address)
ptr = client.pointer_create(secret_key, target_v1)
print(f"Pointer created at: {ptr.address}")

# Read the pointer
pointer = client.pointer_get(ptr.address)
print(f"Points to: {pointer.target.kind} @ {pointer.target.address}")
print(f"Counter: {pointer.counter}")

# Check existence
exists = client.pointer_exists(ptr.address)
print(f"Pointer exists: {exists}")

# Update pointer to point to v2
target_v2 = PointerTarget(kind="chunk", address=data_v2.address)
client.pointer_update(secret_key, target_v2)
print("Pointer updated to v2")

# Read again to verify
pointer = client.pointer_get(ptr.address)
print(f"Now points to: {pointer.target.address}")

print("Pointer CRUD OK!")
