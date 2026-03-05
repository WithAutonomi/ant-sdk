"""Example 07: Graph entry (DAG node) operations.

Graph entries form a directed acyclic graph (DAG) on the network.
Each entry has an owner, content, parent links, and descendant links.
"""

import os

from antd import AntdClient
from antd.models import GraphDescendant

client = AntdClient()

# Generate a random secret key
secret_key = os.urandom(32).hex()

# Create a root graph entry (no parents)
content = os.urandom(32).hex()  # 32 bytes of content
result = client.graph_entry_put(
    owner_secret_key=secret_key,
    parents=[],
    content=content,
    descendants=[],
)
print(f"Graph entry created at: {result.address}")
print(f"Cost: {result.cost} atto tokens")

# Read the graph entry
entry = client.graph_entry_get(result.address)
print(f"Owner: {entry.owner}")
print(f"Content: {entry.content}")
print(f"Parents: {entry.parents}")
print(f"Descendants: {len(entry.descendants)}")

# Check existence
exists = client.graph_entry_exists(result.address)
print(f"Graph entry exists: {exists}")

# Estimate cost for another entry
cost = client.graph_entry_cost(secret_key)
print(f"Cost estimate for new entry: {cost} atto tokens")

print("Graph entry operations OK!")
