"""Example 01: Connect to antd daemon and check health.

Prerequisite: antd daemon running locally (default: http://localhost:8082).
"""

from antd import AntdClient

client = AntdClient()
status = client.health()

print(f"Daemon healthy: {status.ok}")
print(f"Network: {status.network}")

if not status.ok:
    print("ERROR: antd daemon is not healthy")
    raise SystemExit(1)

print("Connection OK!")
