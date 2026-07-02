#!/usr/bin/env bash
#
# Build the Android FFI distribution: cargo-ndk cross-compile -> uniffi-bindgen
# kotlin -> Gradle assembleRelease -> AAR.
#
# Outputs (in $FFI_DIR/build/):
#   ant-android-release.aar  what gets attached to the GH release
#   ant-android.aar.sha256   checksum (informational for now; GH Packages /
#                            Maven would consume this differently)
#
# The publish step (separate script, later) consumes the AAR and pushes to
# ant-android.

set -euo pipefail

# Make sure cargo is on PATH for non-login shells (CI, direct invocation, …).
if ! command -v cargo > /dev/null && [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
fi
command -v cargo > /dev/null || { echo "cargo not found on PATH" >&2; exit 1; }

# Brew tools (gradle, java) for non-login shells too.
if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Pin JDK 17 — Android Gradle Plugin 8.x requires it.
if [ -d /opt/homebrew/opt/openjdk@17 ]; then
    export JAVA_HOME=/opt/homebrew/opt/openjdk@17
    export PATH="$JAVA_HOME/bin:$PATH"
fi

# Default Android SDK / NDK paths — override via env if installed elsewhere.
: "${ANDROID_HOME:=$HOME/Library/Android/sdk}"
: "${ANDROID_NDK_HOME:=$ANDROID_HOME/ndk/26.3.11579264}"
export ANDROID_HOME ANDROID_NDK_HOME

command -v gradle > /dev/null || { echo "gradle not found on PATH" >&2; exit 1; }
[ -d "$ANDROID_NDK_HOME" ] || { echo "NDK not found at $ANDROID_NDK_HOME" >&2; exit 1; }
command -v cargo-ndk > /dev/null || cargo install cargo-ndk

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUST_DIR="$FFI_DIR/rust"
ANDROID_DIR="$FFI_DIR/android"
BUILD_DIR="$FFI_DIR/build"

# ABIs we ship. arm64-v8a + armeabi-v7a are required by Google Play; x86_64
# covers emulators + ChromeOS. 32-bit x86 (i686) is deprecated and omitted —
# add `-t x86` here if you need it.
ABIS=(arm64-v8a armeabi-v7a x86_64)

echo "==> Cross-compiling ant-ffi for Android (${ABIS[*]})"
cd "$RUST_DIR"
NDK_ARGS=()
for abi in "${ABIS[@]}"; do
    NDK_ARGS+=(-t "$abi")
done
cargo ndk "${NDK_ARGS[@]}" build --release -p ant-ffi

echo "==> Building in-crate uniffi-bindgen (host)"
cargo build --release --bin uniffi-bindgen

echo "==> Staging .so files into AAR project"
rm -rf "$ANDROID_DIR/src/main/jniLibs" "$ANDROID_DIR/src/main/kotlin"
mkdir -p "$ANDROID_DIR/src/main/jniLibs"
# Map rust target triples -> Android ABI names. Parallel-arrays form
# instead of `declare -A` (bash 3.2 — macOS default — has no associative
# arrays).
TARGET_PAIRS=(
    "aarch64-linux-android:arm64-v8a"
    "armv7-linux-androideabi:armeabi-v7a"
    "x86_64-linux-android:x86_64"
    "i686-linux-android:x86"
)
for entry in "${TARGET_PAIRS[@]}"; do
    triple="${entry%%:*}"
    abi="${entry##*:}"
    # Skip ABIs not in our active set (lets future builds drop ABIs without
    # touching this script — just edit $ABIS above).
    case " ${ABIS[*]} " in *" $abi "*) ;; *) continue ;; esac
    mkdir -p "$ANDROID_DIR/src/main/jniLibs/$abi"
    cp "$RUST_DIR/target/$triple/release/libant_ffi.so" \
       "$ANDROID_DIR/src/main/jniLibs/$abi/"
done

echo "==> Generating Kotlin bindings"
# Read UniFFI metadata from a freshly cross-compiled Android .so (metadata is
# arch-independent). Do NOT use target/release/libant_ffi.dylib here — this
# script never builds that host cdylib (it only builds the bindgen *binary*),
# so it can be stale and produce bindings that lag the Rust source.
"$RUST_DIR/target/release/uniffi-bindgen" generate \
    --library "$RUST_DIR/target/aarch64-linux-android/release/libant_ffi.so" \
    --language kotlin \
    --out-dir "$ANDROID_DIR/src/main/kotlin"

echo "==> Building AAR via Gradle"
cd "$ANDROID_DIR"
gradle assembleRelease --no-daemon --console=plain

mkdir -p "$BUILD_DIR"
AAR_SRC="$ANDROID_DIR/build/outputs/aar/ant-android-release.aar"
AAR_DST="$BUILD_DIR/ant-android-release.aar"
cp "$AAR_SRC" "$AAR_DST"
CHECKSUM="$(shasum -a 256 "$AAR_DST" | awk '{print $1}')"
echo "$CHECKSUM" > "$AAR_DST.sha256"

echo ""
echo "==> Build complete"
echo "  AAR:    $AAR_DST ($(du -h "$AAR_DST" | awk '{print $1}'))"
echo "  sha256: $CHECKSUM"
