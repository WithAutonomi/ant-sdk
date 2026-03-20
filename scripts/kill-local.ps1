$ErrorActionPreference = "SilentlyContinue"

Write-Host ""
Write-Host "=== Tearing down local environment ===" -ForegroundColor Cyan
Write-Host ""

# Kill by saved PIDs (process tree)
$pidFile = "$env:TEMP\antd-local-pids.json"
if (Test-Path $pidFile) {
    $pids = Get-Content $pidFile -Raw | ConvertFrom-Json

    Write-Host "[1/2] Stopping antd (PID $($pids.antd_pid))..." -ForegroundColor Yellow
    if ($pids.antd_pid) {
        taskkill /F /T /PID $pids.antd_pid 2>$null | Out-Null
    }
    Write-Host "       Done" -ForegroundColor Green

    Write-Host "[2/2] Stopping saorsa devnet (PID $($pids.devnet_pid))..." -ForegroundColor Yellow
    if ($pids.devnet_pid) {
        taskkill /F /T /PID $pids.devnet_pid 2>$null | Out-Null
    }
    Write-Host "       Done" -ForegroundColor Green

    Remove-Item $pidFile -Force
} else {
    # Fallback: kill by process name
    Write-Host "[1/2] Stopping antd..." -ForegroundColor Yellow
    Get-Process -Name antd -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host "       Done" -ForegroundColor Green

    Write-Host "[2/2] Stopping saorsa devnet..." -ForegroundColor Yellow
    Get-Process -Name "saorsa-devnet" -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host "       Done" -ForegroundColor Green
}

# Clean up temp files
Remove-Item "$env:TEMP\devnet-manifest.json" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\saorsa-devnet.log" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\saorsa-devnet.log.err" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\antd.log" -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Environment torn down ===" -ForegroundColor Cyan
Write-Host ""
