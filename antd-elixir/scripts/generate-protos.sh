#!/usr/bin/env bash
# Regenerate the committed Elixir protobuf + gRPC stubs (lib/antd/v1/*.pb.ex)
# from the daemon's protos in ../antd/proto.
#
# protoc-gen-elixir stamps its version into every generated module, so it is
# pinned:
#   mix escript.install hex protobuf 0.16.0
# (then put ~/.mix/escripts on PATH). protoc must be on PATH too; any 3.15+
# works, the Elixir output does not depend on its version.
#
# CI (.github/workflows/proto-drift.yml) runs this script and fails when the
# committed stubs differ from its output, so commit whatever it changes.
#
# Usage (from anywhere): antd-elixir/scripts/generate-protos.sh
set -euo pipefail

PROTOC_GEN_ELIXIR_VERSION="0.16.0"

# The antd/proto/antd/v1 files this SDK ships stubs for.
PROTOS=(chunks common data files health pointers upload wallet)

SDK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SDK_DIR"

found="$(protoc-gen-elixir --version 2>/dev/null | tr -d '\r' || true)"
if [[ "$found" != "$PROTOC_GEN_ELIXIR_VERSION" ]]; then
  echo "error: protoc-gen-elixir $PROTOC_GEN_ELIXIR_VERSION is required (found: ${found:-none})." >&2
  echo "Run: mix escript.install hex protobuf $PROTOC_GEN_ELIXIR_VERSION (and add ~/.mix/escripts to PATH)" >&2
  exit 1
fi

# Start from an empty package, so a proto dropped from PROTOS shows up as a
# deleted stub instead of lingering.
rm -f lib/antd/v1/*.pb.ex

files=()
for p in "${PROTOS[@]}"; do files+=("antd/v1/$p.proto"); done

protoc \
  -I../antd/proto \
  --elixir_out=plugins=grpc:lib \
  "${files[@]}"

echo "Regenerated Elixir stubs under antd-elixir/lib/antd/v1"
