#!/usr/bin/env bash
# Generate Swift gRPC + protobuf stubs from antd/proto/antd/v1/*.proto.
#
# Uses the protoc-gen-swift + protoc-gen-grpc-swift plugins shipped via SwiftPM
# in this package (swift-protobuf + grpc-swift-protobuf). On first run, builds
# the plugins from source via `swift build`; subsequent runs reuse them.
#
# Output: Sources/AntdSdk/Proto/*.pb.swift (protobuf stubs) +
#         *.grpc.swift (gRPC client/server stubs, grpc-swift 2.x V2 codegen).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTO_DIR="$(cd "$PKG_DIR/../antd/proto" && pwd)"
OUT_DIR="$PKG_DIR/Sources/AntdSdk/Proto"

PLUGIN_DIR="$PKG_DIR/.build/$(uname -m)-unknown-linux-gnu/debug"
if [[ ! -x "$PLUGIN_DIR/protoc-gen-swift" || ! -x "$PLUGIN_DIR/protoc-gen-grpc-swift" ]]; then
  echo "Building codegen plugins..."
  (cd "$PKG_DIR" && swift build --product protoc-gen-swift --product protoc-gen-grpc-swift)
fi

export PATH="$PLUGIN_DIR:$PATH"

mkdir -p "$OUT_DIR"

protoc \
  --proto_path="$PROTO_DIR" \
  --swift_out="$OUT_DIR" \
  --swift_opt=Visibility=Public \
  --grpc-swift_out="$OUT_DIR" \
  --grpc-swift_opt=Client=true,Server=true,Visibility=Public \
  "$PROTO_DIR"/antd/v1/common.proto \
  "$PROTO_DIR"/antd/v1/health.proto \
  "$PROTO_DIR"/antd/v1/data.proto \
  "$PROTO_DIR"/antd/v1/chunks.proto \
  "$PROTO_DIR"/antd/v1/files.proto \
  "$PROTO_DIR"/antd/v1/events.proto \
  "$PROTO_DIR"/antd/v1/wallet.proto

echo "Generated:"
ls -la "$OUT_DIR"
