#!/usr/bin/env bash
# Regenerate Dart gRPC + protobuf stubs from the daemon proto files.
#
# Requirements (one-time):
#   dart pub global activate protoc_plugin 22.3.0
#   protoc installed and on PATH (any 3.15+; the Dart output does not depend
#   on its version)
#
# protoc runs the protoc-gen-dart from that activation (in the pub cache's
# bin directory, or $PUB_CACHE/bin), not whichever one is first on PATH.
#
# CI (.github/workflows/proto-drift.yml) runs this script and fails when the
# committed stubs differ from its output, so commit whatever it changes.
#
# Run from this SDK's root:
#   ./tool/generate_proto.sh
set -euo pipefail

PROTOC_PLUGIN_VERSION="22.3.0"

# The antd/proto/antd/v1 files this SDK ships stubs for. They must be
# generated in ONE protoc call: protoc_plugin numbers the `$N` import aliases
# with a counter shared by every file in the call, so generating a subset
# renumbers the aliases in the files it touches.
PROTOS=(common health data chunks files events upload wallet)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROTO_ROOT="$(cd "$SDK_ROOT/../antd/proto" && pwd)"
OUT_DIR="$SDK_ROOT/lib/src/generated"

if ! dart pub global list 2>/dev/null | tr -d '\r' | grep -qx "protoc_plugin $PROTOC_PLUGIN_VERSION"; then
  echo "error: protoc_plugin $PROTOC_PLUGIN_VERSION is required." >&2
  echo "Run: dart pub global activate protoc_plugin $PROTOC_PLUGIN_VERSION" >&2
  exit 1
fi

# The executable `dart pub global activate` installed for the check above.
# On Windows (Git Bash) protoc is a native program, and it needs the output
# directory as a Windows path.
dart_out="$OUT_DIR"
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*)
    default_pub_cache="$HOME/AppData/Local/Pub/Cache"
    dart_out="$(cygpath -m "$OUT_DIR")"
    ;;
  *) default_pub_cache="$HOME/.pub-cache" ;;
esac
PLUGIN="${PUB_CACHE:-$default_pub_cache}/bin/protoc-gen-dart"
if [[ -f "$PLUGIN.bat" ]]; then
  PLUGIN="$PLUGIN.bat"
fi
if [[ ! -f "$PLUGIN" ]]; then
  echo "error: $PLUGIN not found; set PUB_CACHE if your pub cache is elsewhere." >&2
  exit 1
fi

# Start from an empty package, so a proto dropped from PROTOS shows up as
# deleted stubs instead of lingering.
mkdir -p "$OUT_DIR/antd/v1"
rm -f "$OUT_DIR"/antd/v1/*.dart

files=()
for p in "${PROTOS[@]}"; do files+=("$PROTO_ROOT/antd/v1/$p.proto"); done

protoc \
  -I "$PROTO_ROOT" \
  --plugin=protoc-gen-dart="$PLUGIN" \
  --dart_out=grpc:"$dart_out" \
  "${files[@]}"

echo "Regenerated Dart stubs under $OUT_DIR"
