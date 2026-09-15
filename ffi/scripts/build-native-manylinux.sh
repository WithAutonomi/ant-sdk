#!/usr/bin/env bash
# Build ONLY the ant-ffi native library (libant_ffi.so) against the manylinux_2_28
# glibc floor, for packaging into non-Python artifacts (the Antd.Ffi NuGet
# package's runtimes/linux-*/native slots). Same container recipe as
# build-wheel-manylinux.sh, minus the Python steps.
#
# Usage:  ffi/scripts/build-native-manylinux.sh [arch] [out-dir]
#   arch:    x86_64 (default) | aarch64   — must match the host for a native build
#   out-dir: where to copy libant_ffi.so (default: ffi/rust/native-out/<arch>)
set -euo pipefail

ARCH="${1:-x86_64}"
IMAGE="quay.io/pypa/manylinux_2_28_${ARCH}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${2:-$FFI_DIR/rust/native-out/$ARCH}"

CARGO_CACHE="${HOME}/.cache/ant-ffi-cargo"
mkdir -p "$CARGO_CACHE/registry" "$CARGO_CACHE/git" "$OUT_DIR"

echo "=== manylinux native build: $ARCH via $IMAGE ==="
docker run --rm --network host \
  -v "$FFI_DIR":/io \
  -v "$CARGO_CACHE/registry":/root/.cargo/registry \
  -v "$CARGO_CACHE/git":/root/.cargo/git \
  "$IMAGE" bash -euo pipefail -c '
    echo "--- glibc floor: $(ldd --version | head -1) ---"
    dnf install -y -q cmake perl clang golang >/dev/null 2>&1 || \
      yum install -y -q cmake perl clang golang >/dev/null 2>&1 || true
    export RUSTUP_HOME=/root/.rustup CARGO_HOME=/root/.cargo
    export PATH="/root/.cargo/bin:$PATH"
    if ! command -v cargo >/dev/null; then
      curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | \
        sh -s -- -y --default-toolchain stable --profile minimal
    fi
    rustup update stable >/dev/null 2>&1 || true
    echo "--- $(cargo --version) ---"
    cd /io/rust
    cargo build --locked --release -p ant-ffi
    test -f target/release/libant_ffi.so
    chown -R '"$(id -u)"':'"$(id -g)"' /io/rust/target 2>/dev/null || true
  '
cp "$FFI_DIR/rust/target/release/libant_ffi.so" "$OUT_DIR/"
echo "=== glibc symbols required (must stay <= 2.28) ==="
objdump -T "$OUT_DIR/libant_ffi.so" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -3 || true
echo "=== done -> $OUT_DIR/libant_ffi.so ==="
ls -la "$OUT_DIR"
