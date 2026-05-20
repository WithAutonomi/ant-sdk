"""Example 04: Upload and download files and directories.

Creates a temp file, uploads it, then downloads to a new location.
"""

import os
import tempfile

from antd import AntdClient

client = AntdClient()

# Create a temporary file to upload
with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
    f.write("Hello from a file on Autonomi!")
    src_path = f.name

try:
    # Estimate cost
    est = client.file_cost(src_path)
    print(
        f"Estimate: {est.file_size} bytes in {est.chunk_count} chunks, "
        f"storage {est.cost} atto, gas {est.estimated_gas_cost_wei} wei, "
        f"mode {est.payment_mode}"
    )

    # Upload file
    result = client.file_put_public(src_path)
    print(f"File uploaded to: {result.address}")
    print(f"Storage cost: {result.storage_cost_atto} atto, gas: {result.gas_cost_wei} wei")
    print(f"Chunks stored: {result.chunks_stored}, payment mode: {result.payment_mode_used}")

    # Download to new location
    dest_path = src_path + ".downloaded"
    client.file_get_public(result.address, dest_path)
    print(f"Downloaded to: {dest_path}")

    with open(dest_path) as f:
        content = f.read()
    print(f"Content: {content}")
    os.unlink(dest_path)
finally:
    os.unlink(src_path)

print("File upload/download OK!")
