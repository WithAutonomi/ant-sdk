#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FfiDir = Split-Path -Parent $ScriptDir
$RustDir = Join-Path $FfiDir "rust"
$CsharpDir = Join-Path $FfiDir "csharp"
$KotlinDir = Join-Path $FfiDir "kotlin"
$SwiftDir = Join-Path $FfiDir "swift"

Write-Host "=== Step 1: Build Rust FFI library ===" -ForegroundColor Cyan
Push-Location $RustDir
try {
    cargo build --release -p ant-ffi
    if ($LASTEXITCODE -ne 0) { throw "Cargo build failed" }
} finally {
    Pop-Location
}

# Determine library name
if ($IsWindows -or $env:OS -eq "Windows_NT") {
    $LibName = "ant_ffi.dll"
} elseif ($IsMacOS) {
    $LibName = "libant_ffi.dylib"
} else {
    $LibName = "libant_ffi.so"
}

$LibPath = Join-Path $RustDir "target" "release" $LibName
if (-not (Test-Path $LibPath)) {
    throw "Expected library not found at $LibPath"
}
Write-Host "Built: $LibPath"

Write-Host ""
Write-Host "=== Step 2: Generate C# bindings ===" -ForegroundColor Cyan
$GeneratedDir = Join-Path $CsharpDir "AntFfi" "Generated"
New-Item -ItemType Directory -Path $GeneratedDir -Force | Out-Null

# Check for uniffi-bindgen-cs
$bindgenCs = Get-Command uniffi-bindgen-cs -ErrorAction SilentlyContinue
if (-not $bindgenCs) {
    Write-Host "uniffi-bindgen-cs not found. Installing..."
    cargo install uniffi-bindgen-cs --version "0.10.0+v0.29.4"
    if ($LASTEXITCODE -ne 0) { throw "Failed to install uniffi-bindgen-cs" }
}

uniffi-bindgen-cs --library $LibPath --out-dir $GeneratedDir
if ($LASTEXITCODE -ne 0) { throw "uniffi-bindgen-cs failed" }
Write-Host "Generated C# bindings in $GeneratedDir"

Write-Host ""
Write-Host "=== Step 2b: Generate Kotlin bindings ===" -ForegroundColor Cyan
$KotlinGeneratedDir = Join-Path $KotlinDir "AntFfi" "Generated"
New-Item -ItemType Directory -Path $KotlinGeneratedDir -Force | Out-Null

$bindgen = Get-Command uniffi-bindgen -ErrorAction SilentlyContinue
if (-not $bindgen) {
    Write-Host "uniffi-bindgen not found. Installing..."
    cargo install uniffi-bindgen-cli --version "0.29.4"
    if ($LASTEXITCODE -ne 0) { throw "Failed to install uniffi-bindgen-cli" }
}

uniffi-bindgen generate --library $LibPath --language kotlin --out-dir $KotlinGeneratedDir
if ($LASTEXITCODE -ne 0) { throw "uniffi-bindgen (Kotlin) failed" }
Write-Host "Generated Kotlin bindings in $KotlinGeneratedDir"

Write-Host ""
Write-Host "=== Step 2c: Generate Swift bindings ===" -ForegroundColor Cyan
$SwiftGeneratedDir = Join-Path $SwiftDir "AntFfi" "Generated"
New-Item -ItemType Directory -Path $SwiftGeneratedDir -Force | Out-Null

uniffi-bindgen generate --library $LibPath --language swift --out-dir $SwiftGeneratedDir
if ($LASTEXITCODE -ne 0) { throw "uniffi-bindgen (Swift) failed" }
Write-Host "Generated Swift bindings in $SwiftGeneratedDir"

Write-Host ""
Write-Host "=== Step 3: Build .NET solution ===" -ForegroundColor Cyan

# Copy native library
$NativeDir = Join-Path $CsharpDir "AntFfi" "runtimes" "native"
New-Item -ItemType Directory -Path $NativeDir -Force | Out-Null
Copy-Item $LibPath -Destination $NativeDir -Force

Push-Location $CsharpDir
try {
    dotnet build AntFfi.sln
    if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "=== Build complete ===" -ForegroundColor Green
Write-Host "Native library: $LibPath"
Write-Host "C# bindings: $GeneratedDir"
Write-Host "Kotlin bindings: $KotlinGeneratedDir"
Write-Host "Swift bindings: $SwiftGeneratedDir"
