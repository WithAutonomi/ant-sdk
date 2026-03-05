$ErrorActionPreference = "SilentlyContinue"

$autonomiDir = "C:\Users\nbdor\Documents\Projects\autonomi"

Write-Host ""
Write-Host "=== Tearing down local environment ===" -ForegroundColor Cyan
Write-Host ""

# 1. Kill antd
Write-Host "[1/3] Stopping antd..." -ForegroundColor Yellow
Get-Process -Name antd -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host "       Done" -ForegroundColor Green

# 2. Kill local network
Write-Host "[2/3] Stopping local network..." -ForegroundColor Yellow
cmd /c "cargo run --release --manifest-path `"$autonomiDir\Cargo.toml`" --bin antctl -- local kill 2>&1" | Out-Null
Write-Host "       Done" -ForegroundColor Green

# 3. Kill EVM testnet
Write-Host "[3/3] Stopping EVM testnet..." -ForegroundColor Yellow
Get-Process -Name evm-testnet -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host "       Done" -ForegroundColor Green

# 4. Close the spawned terminal windows
Write-Host ""
Write-Host "Closing spawned terminals..." -ForegroundColor Yellow
Get-Process powershell -ErrorAction SilentlyContinue | Where-Object {
    $_.MainWindowTitle -in @("EVM Testnet", "Local Network", "antd")
} | Stop-Process -Force
Write-Host "Done" -ForegroundColor Green

Write-Host ""
Write-Host "=== Environment torn down ===" -ForegroundColor Cyan
Write-Host ""
