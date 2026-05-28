#!/usr/bin/env bash
# Regenerate Dart gRPC + protobuf stubs from the daemon proto files.
#
# Requirements (one-time):
#   dart pub global activate protoc_plugin 22.3.0
#   protoc installed and on PATH
#   On Windows, also add "$HOME/AppData/Local/Pub/Cache/bin" to PATH so
#   protoc can find protoc-gen-dart.bat.
#
# Run from this SDK's root:
#   ./tool/generate_proto.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTO_ROOT="$(cd "$SDK_ROOT/../antd/proto" && pwd)"
OUT_DIR="$SDK_ROOT/lib/src/generated"

mkdir -p "$OUT_DIR"

protoc \
  -I "$PROTO_ROOT" \
  --dart_out=grpc:"$OUT_DIR" \
  "$PROTO_ROOT"/antd/v1/common.proto \
  "$PROTO_ROOT"/antd/v1/health.proto \
  "$PROTO_ROOT"/antd/v1/data.proto \
  "$PROTO_ROOT"/antd/v1/chunks.proto \
  "$PROTO_ROOT"/antd/v1/files.proto \
  "$PROTO_ROOT"/antd/v1/events.proto \
  "$PROTO_ROOT"/antd/v1/upload.proto

echo "Regenerated Dart stubs under $OUT_DIR"
