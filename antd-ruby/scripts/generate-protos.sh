#!/usr/bin/env bash
# Regenerate the committed Ruby protobuf + gRPC stubs (lib/antd/v1/*_pb.rb)
# from the daemon's protos in ../antd/proto.
#
# The grpc-tools gem bundles its own protoc, so pinning the gem pins the
# whole toolchain:
#   gem install grpc-tools -v 1.84.0
#
# CI (.github/workflows/proto-drift.yml) runs this script and fails when the
# committed stubs differ from its output, so commit whatever it changes.
#
# Usage (from anywhere): antd-ruby/scripts/generate-protos.sh
set -euo pipefail

GRPC_TOOLS_VERSION="1.84.0"

# The antd/proto/antd/v1 files this SDK ships stubs for.
PROTOS=(chunks common data files health upload wallet)

SDK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SDK_DIR"

# RubyGems binstubs take a leading _VERSION_ argument to run that exact
# installed version of the gem.
if ! grpc_tools_ruby_protoc "_${GRPC_TOOLS_VERSION}_" --version >/dev/null 2>&1; then
  echo "error: the grpc-tools gem $GRPC_TOOLS_VERSION is required." >&2
  echo "Run: gem install grpc-tools -v $GRPC_TOOLS_VERSION" >&2
  exit 1
fi

# Start from an empty package, so a proto dropped from PROTOS shows up as
# deleted stubs instead of lingering.
rm -f lib/antd/v1/*_pb.rb

files=()
for p in "${PROTOS[@]}"; do files+=("antd/v1/$p.proto"); done

grpc_tools_ruby_protoc "_${GRPC_TOOLS_VERSION}_" \
  -I../antd/proto \
  --ruby_out=lib --grpc_out=lib \
  "${files[@]}"

echo "Regenerated Ruby stubs under antd-ruby/lib/antd/v1"
