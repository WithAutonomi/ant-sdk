#!/usr/bin/env bash
# Run Python SDK integration tests (REST + gRPC)
# Requires a running antd daemon with REST on :8080 and gRPC on :50051

set -euo pipefail

REST_URL="${1:-http://localhost:8080}"
GRPC_TARGET="${2:-localhost:50051}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
failed=0

echo ""
echo "===== Python SDK Integration Tests ====="
echo ""

# --- REST ---
echo "--- Running REST tests ---"
python "$SCRIPT_DIR/scripts/test_rest.py" "$REST_URL" || ((failed++))

echo ""

# --- gRPC ---
echo "--- Running gRPC tests ---"
python "$SCRIPT_DIR/scripts/test_grpc.py" "$GRPC_TARGET" || ((failed++))

# --- Summary ---
echo ""
if [ "$failed" -eq 0 ]; then
    echo "All test suites passed."
else
    echo "$failed test suite(s) had failures."
fi

exit "$failed"
