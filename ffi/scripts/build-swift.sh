#!/usr/bin/env bash
#
# Build the Swift FFI distribution: cargo cross-compile -> uniffi-bindgen ->
# xcframework -> zip + sha256.
#
# Outputs (in $FFI_DIR/build/):
#   AntFfi.xcframework/            assembled xcframework (3 slices)
#   AntFfi.xcframework.zip         what gets attached to the GH release
#   AntFfi.xcframework.zip.sha256  checksum for Package.swift binaryTarget
#   ant_ffi.swift                  Swift glue to commit into ant-swift repo
#
# The publish step (separate script) consumes these and pushes to ant-swift.

set -euo pipefail

# Make sure cargo is on PATH for non-login shells (CI, direct invocation, …).
if ! command -v cargo > /dev/null && [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
fi
command -v cargo > /dev/null || { echo "cargo not found on PATH" >&2; exit 1; }
command -v xcodebuild > /dev/null || { echo "xcodebuild not found on PATH" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUST_DIR="$FFI_DIR/rust"
BUILD_DIR="$FFI_DIR/build"
XCF_DIR="$BUILD_DIR/AntFfi.xcframework"

# Deployment targets — must match Package.swift's .iOS(.v16) / .macOS(.v13)
# declarations in ant-swift. Setting these silences "built for newer X version"
# warnings at consumer link time. iOS<13 also fails to link due to missing
# '___chkstk_darwin' symbol.
export IPHONEOS_DEPLOYMENT_TARGET=16.0
export MACOSX_DEPLOYMENT_TARGET=13.0

IOS_TARGETS=(
    aarch64-apple-ios       # iOS device
    aarch64-apple-ios-sim   # iOS simulator on Apple Silicon
)
# x86_64-apple-ios-sim intentionally omitted (Intel Mac simulator). Add to
# IOS_TARGETS and to the xcframework assembly below if Intel-Mac dev support
# is needed; lipo into the existing ios-arm64-simulator slice rather than a
# separate slice.

cd "$RUST_DIR"

echo "==> Building Rust static libs"
for target in "${IOS_TARGETS[@]}"; do
    echo "  $target"
    cargo build --release -p ant-ffi --target "$target"
done
echo "  $(rustc -vV | awk '/host:/ {print $2}') (host, for macOS slice + bindgen)"
cargo build --release -p ant-ffi

echo "==> Building in-crate uniffi-bindgen"
cargo build --release --bin uniffi-bindgen

echo "==> Generating Swift bindings"
GEN_DIR="$BUILD_DIR/generated-swift"
rm -rf "$GEN_DIR"
mkdir -p "$GEN_DIR"
"$RUST_DIR/target/release/uniffi-bindgen" generate \
    --library "$RUST_DIR/target/release/libant_ffi.dylib" \
    --language swift \
    --out-dir "$GEN_DIR"

echo "==> Assembling xcframework"
rm -rf "$XCF_DIR"
SLICE_DIR="$BUILD_DIR/slices"
rm -rf "$SLICE_DIR"

# Each slice needs: libant_ffi.a + Headers/{ant_ffiFFI.h, module.modulemap}
# The modulemap inside Headers must be named exactly `module.modulemap` (not
# the uniffi-emitted `ant_ffiFFI.modulemap`) for Xcode to find it.
prepare_slice() {
    local slice_name="$1"
    local lib_src="$2"
    local out="$SLICE_DIR/$slice_name"
    mkdir -p "$out/Headers"
    cp "$lib_src" "$out/libant_ffi.a"
    cp "$GEN_DIR/ant_ffiFFI.h" "$out/Headers/"
    cp "$GEN_DIR/ant_ffiFFI.modulemap" "$out/Headers/module.modulemap"
}

prepare_slice "ios-arm64"           "$RUST_DIR/target/aarch64-apple-ios/release/libant_ffi.a"
prepare_slice "ios-arm64-simulator" "$RUST_DIR/target/aarch64-apple-ios-sim/release/libant_ffi.a"
prepare_slice "macos-arm64"         "$RUST_DIR/target/release/libant_ffi.a"

xcodebuild -create-xcframework \
    -library "$SLICE_DIR/ios-arm64/libant_ffi.a"           -headers "$SLICE_DIR/ios-arm64/Headers" \
    -library "$SLICE_DIR/ios-arm64-simulator/libant_ffi.a" -headers "$SLICE_DIR/ios-arm64-simulator/Headers" \
    -library "$SLICE_DIR/macos-arm64/libant_ffi.a"         -headers "$SLICE_DIR/macos-arm64/Headers" \
    -output "$XCF_DIR" > /dev/null

echo "==> Packaging zip + checksum"
ZIP_PATH="$BUILD_DIR/AntFfi.xcframework.zip"
rm -f "$ZIP_PATH"
( cd "$BUILD_DIR" && zip -qr "AntFfi.xcframework.zip" "AntFfi.xcframework" )
# `swift package compute-checksum` is the canonical way to compute the value
# that goes into Package.swift's binaryTarget(checksum:). Fall back to shasum
# if Swift isn't on PATH (CI runners sometimes need PATH setup).
if command -v swift > /dev/null; then
    CHECKSUM="$(swift package compute-checksum "$ZIP_PATH")"
else
    CHECKSUM="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
fi
echo "$CHECKSUM" > "$ZIP_PATH.sha256"

# Copy generated Swift glue to a stable location for the publish step.
cp "$GEN_DIR/ant_ffi.swift" "$BUILD_DIR/ant_ffi.swift"

echo ""
echo "==> Build complete"
echo "  xcframework: $XCF_DIR"
echo "  zip:         $ZIP_PATH ($(du -h "$ZIP_PATH" | awk '{print $1}'))"
echo "  sha256:      $CHECKSUM"
echo "  swift glue:  $BUILD_DIR/ant_ffi.swift"
