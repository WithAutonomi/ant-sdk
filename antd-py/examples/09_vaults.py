"""Example 09: Vault store and retrieve.

Vaults provide private encrypted storage keyed by a secret key.
Data is encrypted client-side before being stored on the network.
"""

import os

from antd import AntdClient

client = AntdClient()

# Generate a random secret key for the vault
secret_key = os.urandom(32).hex()

# Store data in the vault
payload = b"Secret vault data that is encrypted"
content_type = 42  # application-defined type
cost = client.vault_put(secret_key, payload, content_type)
print(f"Vault store cost: {cost} atto tokens")

# Retrieve from vault
vault = client.vault_get(secret_key)
print(f"Content type: {vault.content_type}")
print(f"Data: {vault.data.decode()}")

assert vault.data == payload, "Vault round-trip mismatch!"
assert vault.content_type == content_type, "Content type mismatch!"

print("Vault round-trip OK!")
