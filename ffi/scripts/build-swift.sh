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

# Framework version string comes from the crate version (which tracks the
# released SDK version) instead of a hardcoded value drifting out of date.
ANT_FFI_VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' "$RUST_DIR/ant-ffi/Cargo.toml" | head -1)"
[ -n "$ANT_FFI_VERSION" ] || { echo "failed to read version from ant-ffi/Cargo.toml" >&2; exit 1; }

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

# Each slice is a DYNAMIC `.framework` built from the cdylib — NOT a static
# `.a` + `Headers/`. A static-library xcframework copies its `module.modulemap`
# into the consumer's shared `BUILT_PRODUCTS_DIR/include/`, which collides with
# any *other* static xcframework that does the same (e.g. Reown AppKit's
# `yttrium`): "Multiple commands produce .../include/module.modulemap". A
# dynamic framework keeps its modulemap inside `Modules/`, so multiple such
# frameworks coexist in one app. (Linear V2-532.)
FW_NAME="ant_ffiFFI"   # must match the uniffi module name the Swift glue imports

write_modulemap() {
    cat > "$1" <<EOF
framework module $FW_NAME {
    umbrella header "$FW_NAME.h"
    export *
}
EOF
}

# $1 plist path, $2 platform (ios|macos)
write_plist() {
    local minkey minver
    if [ "$2" = "macos" ]; then
        minkey="LSMinimumSystemVersion"; minver="$MACOSX_DEPLOYMENT_TARGET"
    else
        minkey="MinimumOSVersion"; minver="$IPHONEOS_DEPLOYMENT_TARGET"
    fi
    # CFBundleIdentifier disallows underscores — strip them from the module name.
    local bundle_id="com.autonomi.${FW_NAME//_/}"
    cat > "$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$FW_NAME</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$FW_NAME</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$ANT_FFI_VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>$minkey</key><string>$minver</string>
</dict></plist>
EOF
}

# $1 slice dir, $2 cdylib path, $3 platform (ios|macos)
prepare_framework() {
    local slice_name="$1" dylib_src="$2" platform="$3"
    local fw="$SLICE_DIR/$slice_name/$FW_NAME.framework"

    if [ "$platform" = "macos" ]; then
        # macOS frameworks use a versioned bundle (Versions/A + symlinks).
        local V="$fw/Versions/A"
        mkdir -p "$V/Headers" "$V/Modules" "$V/Resources"
        cp "$dylib_src" "$V/$FW_NAME"
        install_name_tool -id "@rpath/$FW_NAME.framework/Versions/A/$FW_NAME" "$V/$FW_NAME"
        cp "$GEN_DIR/$FW_NAME.h" "$V/Headers/"
        write_modulemap "$V/Modules/module.modulemap"
        write_plist "$V/Resources/Info.plist" "$platform"
        # Required-reason-API privacy manifest (ITMS-91053); macOS bundles
        # keep resources under Versions/A/Resources.
        cp "$SCRIPT_DIR/PrivacyInfo.xcprivacy" "$V/Resources/PrivacyInfo.xcprivacy"
        ln -s "A" "$fw/Versions/Current"
        ln -s "Versions/Current/$FW_NAME" "$fw/$FW_NAME"
        ln -s "Versions/Current/Headers" "$fw/Headers"
        ln -s "Versions/Current/Modules" "$fw/Modules"
        ln -s "Versions/Current/Resources" "$fw/Resources"
    else
        # iOS / simulator frameworks are flat.
        mkdir -p "$fw/Headers" "$fw/Modules"
        cp "$dylib_src" "$fw/$FW_NAME"
        install_name_tool -id "@rpath/$FW_NAME.framework/$FW_NAME" "$fw/$FW_NAME"
        cp "$GEN_DIR/$FW_NAME.h" "$fw/Headers/"
        write_modulemap "$fw/Modules/module.modulemap"
        write_plist "$fw/Info.plist" "$platform"
        # Required-reason-API privacy manifest (ITMS-91053); flat frameworks
        # carry it at the bundle root.
        cp "$SCRIPT_DIR/PrivacyInfo.xcprivacy" "$fw/PrivacyInfo.xcprivacy"
    fi
}

prepare_framework "ios-arm64"           "$RUST_DIR/target/aarch64-apple-ios/release/libant_ffi.dylib"     "ios"
prepare_framework "ios-arm64-simulator" "$RUST_DIR/target/aarch64-apple-ios-sim/release/libant_ffi.dylib" "ios"
prepare_framework "macos-arm64"         "$RUST_DIR/target/release/libant_ffi.dylib"                        "macos"

xcodebuild -create-xcframework \
    -framework "$SLICE_DIR/ios-arm64/$FW_NAME.framework" \
    -framework "$SLICE_DIR/ios-arm64-simulator/$FW_NAME.framework" \
    -framework "$SLICE_DIR/macos-arm64/$FW_NAME.framework" \
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
