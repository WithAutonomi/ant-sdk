#!/usr/bin/env bash
# Run C# SDK integration tests (REST + gRPC)
# Requires a running antd daemon with REST on :8080 and gRPC on :50051

set -euo pipefail

REST_ENDPOINT="${1:-http://localhost:8080}"
GRPC_ENDPOINT="${2:-http://localhost:50051}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
failed=0

echo ""
echo "===== C# SDK Integration Tests ====="
echo ""

# --- REST ---
echo "--- Running REST tests ---"
dotnet run --project "$SCRIPT_DIR/Antd.Sdk.Tests" -- --transport rest --endpoint "$REST_ENDPOINT" || ((failed++))

echo ""

# --- gRPC ---
echo "--- Running gRPC tests ---"
dotnet run --project "$SCRIPT_DIR/Antd.Sdk.Tests" -- --transport grpc --endpoint "$GRPC_ENDPOINT" || ((failed++))

# --- Summary ---
echo ""
if [ "$failed" -eq 0 ]; then
    echo "All test suites passed."
else
    echo "$failed test suite(s) had failures."
fi

exit "$failed"
