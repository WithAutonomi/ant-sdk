#!/usr/bin/env bash
# Regenerate the committed Go protobuf + gRPC stubs (proto/antd/v1/*.pb.go)
# from the daemon's protos in ../antd/proto.
#
# protoc-gen-go and protoc-gen-go-grpc stamp their own version, and protoc's,
# into every file header, so all three are pinned here. The two plugins are
# built at the pinned versions into a throwaway directory; protoc itself must
# be on PATH at exactly PROTOC_VERSION:
#   https://github.com/protocolbuffers/protobuf/releases/tag/v34.1
#
# CI (.github/workflows/proto-drift.yml) runs this script and fails when the
# committed stubs differ from its output, so commit whatever it changes.
#
# Usage (from anywhere): antd-go/scripts/generate-protos.sh
set -euo pipefail

PROTOC_VERSION="34.1"
PROTOC_GEN_GO_VERSION="v1.36.12"
PROTOC_GEN_GO_GRPC_VERSION="v1.6.2"

# The antd/proto/antd/v1 files this SDK ships stubs for.
PROTOS=(chunks common data events files health manifests upload verify wallet)

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

found="$(protoc --version 2>/dev/null | tr -d '\r' || true)"
if [[ "$found" != "libprotoc $PROTOC_VERSION" ]]; then
  echo "error: protoc $PROTOC_VERSION is required (found: ${found:-none})." >&2
  echo "Its version is stamped into the generated headers. Download it from" >&2
  echo "https://github.com/protocolbuffers/protobuf/releases/tag/v$PROTOC_VERSION" >&2
  exit 1
fi

PLUGIN_DIR="$(mktemp -d)"
trap 'rm -rf "$PLUGIN_DIR"' EXIT
GOBIN="$PLUGIN_DIR" go install "google.golang.org/protobuf/cmd/protoc-gen-go@$PROTOC_GEN_GO_VERSION"
GOBIN="$PLUGIN_DIR" go install "google.golang.org/grpc/cmd/protoc-gen-go-grpc@$PROTOC_GEN_GO_GRPC_VERSION"

# Start from an empty package, so a proto dropped from PROTOS shows up as a
# deleted stub instead of lingering.
rm -f antd-go/proto/antd/v1/*.pb.go

files=()
for p in "${PROTOS[@]}"; do files+=("antd/proto/antd/v1/$p.proto"); done

PATH="$PLUGIN_DIR:$PATH" protoc \
  --proto_path=antd/proto \
  --go_out=antd-go/proto --go_opt=paths=source_relative \
  --go-grpc_out=antd-go/proto --go-grpc_opt=paths=source_relative \
  "${files[@]}"

echo "Regenerated Go stubs under antd-go/proto/antd/v1"
