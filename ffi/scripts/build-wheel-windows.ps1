#!/usr/bin/env pwsh
# Build a Windows (win_amd64) Python wheel for the ant-ffi bindings.
#
# Compiles ant_ffi.dll natively (x86_64-pc-windows-msvc), generates the
# bindings, and packages a `win_amd64` wheel. delvewheel is the Windows
# analogue of auditwheel/delocate — it bundles any non-system DLL the native
# library needs (e.g. the VC runtime) so the wheel is self-contained.
#
# Run on Windows with the MSVC toolchain + rustup. Output -> ffi/python/wheelhouse/.
$ErrorActionPreference = "Stop"

$FfiDir  = Split-Path -Parent $PSScriptRoot          # scripts/ -> ffi/
$RustDir = Join-Path $FfiDir "rust"
$PyDir   = Join-Path $FfiDir "python"
$PyPkg   = Join-Path $PyDir  "ant_ffi"

Write-Host "=== [1/6] build ant-ffi + bindgen (x86_64-pc-windows-msvc) ==="
Push-Location $RustDir
cargo build --release -p ant-ffi
cargo build --release --bin uniffi-bindgen
$Dll = Join-Path $RustDir "target\release\ant_ffi.dll"
if (!(Test-Path $Dll)) { throw "missing native library: $Dll" }
Pop-Location

Write-Host "=== [2/6] bundle DLL next to the module ==="
New-Item -ItemType Directory -Force -Path $PyPkg | Out-Null
Copy-Item $Dll $PyPkg -Force

Write-Host "=== [3/6] generate bindings ==="
$Bindgen = Join-Path $RustDir "target\release\uniffi-bindgen.exe"
& $Bindgen generate --library $Dll --language python --out-dir $PyPkg
if ($LASTEXITCODE -ne 0) { throw "uniffi-bindgen failed" }

Write-Host "=== [4/6] build wheel (setup.py forces py3-none-win_amd64) ==="
$Venv = Join-Path $env:TEMP "antffi-wheel-venv"
python -m venv $Venv
& (Join-Path $Venv "Scripts\python.exe") -m pip install -q --upgrade pip setuptools wheel delvewheel
$Py = Join-Path $Venv "Scripts\python.exe"
Push-Location $PyDir
Remove-Item -Recurse -Force build, dist, *.egg-info -ErrorAction SilentlyContinue
& $Py setup.py -q bdist_wheel --plat-name win_amd64
if ($LASTEXITCODE -ne 0) { throw "wheel build failed" }

Write-Host "=== [5/6] delvewheel repair: bundle non-system DLLs ==="
New-Item -ItemType Directory -Force -Path wheelhouse | Out-Null
$Whl = (Get-ChildItem dist\*.whl | Select-Object -First 1).FullName
& $Py -m delvewheel repair $Whl -w wheelhouse -v
if ($LASTEXITCODE -ne 0) { throw "delvewheel repair failed" }

Write-Host "=== [6/6] install repaired wheel into a clean venv + import check ==="
$CheckVenv = Join-Path $env:TEMP "antffi-wheel-check-venv"
if (Test-Path $CheckVenv) { Remove-Item -Recurse -Force $CheckVenv }
python -m venv $CheckVenv
$CheckPy = Join-Path $CheckVenv "Scripts\python.exe"
$Repaired = (Get-ChildItem wheelhouse\ant_sdk-*.whl | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
& $CheckPy -m pip install -q $Repaired
if ($LASTEXITCODE -ne 0) { throw "installed-wheel pip install failed" }
# Import from outside the source tree so the checkout can't mask the install.
Push-Location $env:TEMP
& $CheckPy -c "import ant_ffi; print('ok: ant_ffi', ant_ffi.ant_ffi_version())"
$ImportOk = $LASTEXITCODE -eq 0
Pop-Location
if (-not $ImportOk) { throw "installed-wheel import check failed" }

Write-Host "=== done -> $PyDir\wheelhouse\ ==="
Get-ChildItem wheelhouse
Pop-Location
