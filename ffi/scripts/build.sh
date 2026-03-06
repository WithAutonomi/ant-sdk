#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FFI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUST_DIR="$FFI_DIR/rust"
CSHARP_DIR="$FFI_DIR/csharp"
KOTLIN_DIR="$FFI_DIR/kotlin"
SWIFT_DIR="$FFI_DIR/swift"

echo "=== Step 1: Build Rust FFI library ==="
cd "$RUST_DIR"
cargo build --release -p ant-ffi

# Determine the native library name based on platform
case "$(uname -s)" in
    Linux*)   LIB_NAME="libant_ffi.so" ;;
    Darwin*)  LIB_NAME="libant_ffi.dylib" ;;
    MINGW*|MSYS*|CYGWIN*) LIB_NAME="ant_ffi.dll" ;;
    *)        echo "Unsupported platform: $(uname -s)"; exit 1 ;;
esac

LIB_PATH="$RUST_DIR/target/release/$LIB_NAME"
if [ ! -f "$LIB_PATH" ]; then
    echo "ERROR: Expected library not found at $LIB_PATH"
    exit 1
fi
echo "Built: $LIB_PATH"

echo ""
echo "=== Step 2: Generate C# bindings ==="
GENERATED_DIR="$CSHARP_DIR/AntFfi/Generated"
mkdir -p "$GENERATED_DIR"

# uniffi-bindgen-cs must be installed: cargo install uniffi-bindgen-cs --version 0.10.0+v0.29.4
if ! command -v uniffi-bindgen-cs &> /dev/null; then
    echo "uniffi-bindgen-cs not found. Installing..."
    cargo install uniffi-bindgen-cs --version "0.10.0+v0.29.4"
fi

uniffi-bindgen-cs --library "$LIB_PATH" --out-dir "$GENERATED_DIR"
echo "Generated C# bindings in $GENERATED_DIR"

echo ""
echo "=== Step 2b: Generate Kotlin bindings ==="
KOTLIN_GENERATED_DIR="$KOTLIN_DIR/AntFfi/Generated"
mkdir -p "$KOTLIN_GENERATED_DIR"

if ! command -v uniffi-bindgen &> /dev/null; then
    echo "uniffi-bindgen not found. Installing..."
    cargo install uniffi-bindgen-cli --version "0.29.4"
fi

uniffi-bindgen generate --library "$LIB_PATH" --language kotlin --out-dir "$KOTLIN_GENERATED_DIR"
echo "Generated Kotlin bindings in $KOTLIN_GENERATED_DIR"

echo ""
echo "=== Step 2c: Generate Swift bindings ==="
SWIFT_GENERATED_DIR="$SWIFT_DIR/AntFfi/Generated"
mkdir -p "$SWIFT_GENERATED_DIR"

uniffi-bindgen generate --library "$LIB_PATH" --language swift --out-dir "$SWIFT_GENERATED_DIR"
echo "Generated Swift bindings in $SWIFT_GENERATED_DIR"

echo ""
echo "=== Step 3: Build .NET solution ==="

# Copy native library to output directory
NATIVE_DIR="$CSHARP_DIR/AntFfi/runtimes/native"
mkdir -p "$NATIVE_DIR"
cp "$LIB_PATH" "$NATIVE_DIR/"

cd "$CSHARP_DIR"
dotnet build AntFfi.sln

echo ""
echo "=== Step 4: Build Kotlin FFI project ==="
if command -v gradle &> /dev/null || [ -f "$KOTLIN_DIR/gradlew" ]; then
    cd "$KOTLIN_DIR"
    if [ -f "gradlew" ]; then
        ./gradlew build
    else
        gradle build
    fi
    echo "Kotlin FFI project built"
else
    echo "Gradle not found, skipping Kotlin build. Run 'gradle build' in $KOTLIN_DIR manually."
fi

echo ""
echo "=== Build complete ==="
echo "Native library: $LIB_PATH"
echo "C# bindings: $GENERATED_DIR"
echo "Kotlin bindings: $KOTLIN_GENERATED_DIR"
echo "Swift bindings: $SWIFT_GENERATED_DIR"
