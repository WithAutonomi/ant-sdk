#!/usr/bin/env bash
# Install a built ant-sdk wheel into a throwaway venv and import it.
#
# A wheel missing the generated ant_ffi.py or the native library installs
# cleanly and only fails on first import — setup.py refuses to build one, and
# this is the matching post-build proof that the wheel that DID get built
# actually works: fresh venv, pip install, `import ant_ffi`, print the version.
#
# Usage: check-python-wheel.sh [path-to-wheel]
# With no argument, checks the newest ant_sdk-*.whl in ffi/python/wheelhouse/
# (falling back to ffi/python/dist/). Override the interpreter with PYTHON=.
set -euo pipefail

FFI_DIR="$(cd "$(dirname "$0")/.." && pwd)"

WHEEL="${1:-}"
if [[ -z "$WHEEL" ]]; then
    for d in "$FFI_DIR/python/wheelhouse" "$FFI_DIR/python/dist"; do
        candidate="$(ls -t "$d"/ant_sdk-*.whl 2>/dev/null | head -n 1 || true)"
        if [[ -n "$candidate" ]]; then
            WHEEL="$candidate"
            break
        fi
    done
fi
if [[ -z "$WHEEL" || ! -f "$WHEEL" ]]; then
    echo "error: no ant_sdk-*.whl found in wheelhouse/ or dist/; pass a path" >&2
    exit 2
fi

PYTHON="${PYTHON:-python3}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$PYTHON" -m venv "$TMP/venv"
VPY="$TMP/venv/bin/python"
[[ -x "$VPY" ]] || VPY="$TMP/venv/Scripts/python.exe"   # Windows venv layout

"$VPY" -m pip install --quiet "$WHEEL"

# Import from the temp dir so the repo checkout can't mask the installed
# package.
(cd "$TMP" && "$VPY" -c 'import ant_ffi; print("ok: ant_ffi", ant_ffi.ant_ffi_version())')
echo "=== wheel check passed: $WHEEL ==="
