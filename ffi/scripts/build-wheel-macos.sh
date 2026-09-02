#!/usr/bin/env bash
# Build a universal2 macOS Python wheel for the ant-ffi bindings.
#
# Compiles the native lib for both arm64 (Apple Silicon) and x86_64 (Intel),
# lipo-fuses them into one fat dylib, and packages a single
# `macosx_11_0_universal2` wheel that installs on both Mac architectures.
# Deployment target is pinned to 11.0 (arm64's floor) so the tag is honest.
# `delocate` is the macOS analogue of auditwheel — it verifies the dylib is
# self-contained and carries both arches.
#
# Run on macOS with Xcode CLT + rustup. Output -> ffi/python/wheelhouse/.
set -euo pipefail

export MACOSX_DEPLOYMENT_TARGET=11.0
PLAT_TAG="macosx_11_0_universal2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUST_DIR="$FFI_DIR/rust"
PY_PKG="$FFI_DIR/python/ant_ffi"

echo "=== [1/7] add x86_64 target (arm64 is native here) ==="
rustup target add x86_64-apple-darwin aarch64-apple-darwin >/dev/null

echo "=== [2/7] build both arches (deployment target $MACOSX_DEPLOYMENT_TARGET) ==="
cd "$RUST_DIR"
cargo build --release -p ant-ffi --target aarch64-apple-darwin
cargo build --release -p ant-ffi --target x86_64-apple-darwin
ARM=target/aarch64-apple-darwin/release/libant_ffi.dylib
X86=target/x86_64-apple-darwin/release/libant_ffi.dylib

echo "=== [3/7] lipo -> universal2 dylib ==="
mkdir -p "$PY_PKG"
lipo -create -output "$PY_PKG/libant_ffi.dylib" "$ARM" "$X86"
lipo -info "$PY_PKG/libant_ffi.dylib"

echo "=== [4/7] generate bindings (arch-independent) ==="
# The in-crate bindgen was built for the native (arm64) host by the build above.
BINDGEN=target/aarch64-apple-darwin/release/uniffi-bindgen
"$BINDGEN" generate --library "$ARM" --language python --out-dir "$PY_PKG"

echo "=== [5/7] build universal2 wheel ==="
VENV="$(mktemp -d)/venv"
python3 -m venv "$VENV"
# shellcheck disable=SC1091
source "$VENV/bin/activate"
pip install -q --upgrade pip setuptools wheel delocate
cd "$FFI_DIR/python"
rm -rf build dist ./*.egg-info
python setup.py -q bdist_wheel --plat-name "$PLAT_TAG"

echo "=== [6/7] delocate: verify self-contained + both arches ==="
mkdir -p wheelhouse
delocate-listdeps --all dist/*.whl || true
delocate-wheel --require-archs x86_64,arm64 -w wheelhouse -v dist/*.whl

echo "=== [7/7] install repaired wheel into a clean venv + import check ==="
"$SCRIPT_DIR/check-python-wheel.sh"

echo "=== done -> $FFI_DIR/python/wheelhouse/ ==="
ls -la wheelhouse/
