#!/usr/bin/env bash
# Build a manylinux-honest Python wheel for the ant-ffi bindings.
#
# Runs on any Linux host with Docker. The native library is compiled INSIDE a
# manylinux_2_28 container (glibc 2.28, AlmaLinux 8) — never against the host's
# glibc — so the wheel installs on any distro from ~2019 on (RHEL8, Ubuntu 20.04+,
# Debian 10+). auditwheel is the authority on the final tag.
#
# Usage (from anywhere):  ffi/scripts/build-wheel-manylinux.sh [arch]
#   arch: x86_64 (default) | aarch64
# Output wheel lands in ffi/python/wheelhouse/.
set -euo pipefail

ARCH="${1:-x86_64}"
IMAGE="quay.io/pypa/manylinux_2_28_${ARCH}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Persist the cargo cache across runs so only the first build pays the full
# ant-core compile.
CARGO_CACHE="${HOME}/.cache/ant-ffi-cargo"
mkdir -p "$CARGO_CACHE/registry" "$CARGO_CACHE/git"

echo "=== manylinux wheel build: $ARCH via $IMAGE ==="
# --network host: required when the Docker daemon itself runs inside an
# unprivileged incus/LXC container. Newer Docker applies the namespaced sysctl
# net.ipv4.ip_unprivileged_port_start on container init, which the nested
# container can't write ("permission denied"); host networking skips per-netns
# sysctls. The build only needs outbound internet (rustup/crates.io/pip/dnf).
docker run --rm --network host \
  -v "$FFI_DIR":/io \
  -v "$CARGO_CACHE/registry":/root/.cargo/registry \
  -v "$CARGO_CACHE/git":/root/.cargo/git \
  -e ARCH="$ARCH" \
  "$IMAGE" bash -euo pipefail -c '
    echo "--- host glibc floor: $(ldd --version | head -1) ---"

    # Build deps some crypto crates want (ring: perl/clang; aws-lc-sys: cmake/go).
    dnf install -y -q cmake perl clang golang >/dev/null 2>&1 || \
      yum install -y -q cmake perl clang golang >/dev/null 2>&1 || true

    # Rust (crate needs 1.82+).
    export RUSTUP_HOME=/root/.rustup CARGO_HOME=/root/.cargo
    export PATH="/root/.cargo/bin:$PATH"
    # Use latest stable: the ant-core graph (alloy 1.8.x) needs rustc >= 1.91.
    if ! command -v cargo >/dev/null; then
      curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | \
        sh -s -- -y --default-toolchain stable --profile minimal
    fi
    rustup update stable >/dev/null 2>&1 || true
    echo "--- $(cargo --version) ---"

    # 1. Build the native lib + the in-crate uniffi-bindgen.
    cd /io/rust
    cargo build --release -p ant-ffi
    LIB=/io/rust/target/release/libant_ffi.so
    test -f "$LIB"

    # 2. Generate the pure-Python bindings and bundle the fresh .so.
    OUT=/io/python/ant_ffi
    mkdir -p "$OUT"
    /io/rust/target/release/uniffi-bindgen generate \
      --library "$LIB" --language python --out-dir "$OUT"
    cp "$LIB" "$OUT/"

    # 3. Build a platform-tagged wheel (setup.py forces py3-none-<plat>).
    PY=/opt/python/cp312-cp312/bin/python
    # setuptools+wheel are needed explicitly: modern CPython does not bundle
    # setuptools, and we build with --no-isolation (setup.py imports it).
    "$PY" -m pip install -q --upgrade pip build auditwheel setuptools wheel
    cd /io/python
    rm -rf build dist *.egg-info
    "$PY" -m build --wheel --no-isolation

    # 4. auditwheel: verify glibc floor, bundle external libs, honest retag.
    echo "=== auditwheel show (pre-repair) ==="
    "$PY" -m auditwheel show dist/*.whl
    "$PY" -m auditwheel repair dist/*.whl -w /io/python/wheelhouse/
    echo "=== auditwheel show (repaired) ==="
    "$PY" -m auditwheel show /io/python/wheelhouse/*.whl
    chown -R '"$(id -u)"':'"$(id -g)"' /io/python/wheelhouse /io/python/ant_ffi /io/python/dist 2>/dev/null || true
  '
# Native-arch hosts only: pip refuses a foreign-arch wheel, so a cross build
# (x86_64 host, aarch64 target) can't self-check here.
if [[ "$(uname -m)" == "$ARCH" ]]; then
  echo "=== install repaired wheel into a clean venv + import check ==="
  "$SCRIPT_DIR/check-python-wheel.sh"
else
  echo "=== skipping venv import check: host $(uname -m) != target $ARCH ==="
fi

echo "=== done -> $FFI_DIR/python/wheelhouse/ ==="
ls -la "$FFI_DIR/python/wheelhouse/"
