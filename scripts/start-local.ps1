$ErrorActionPreference = "Stop"

$autonomiDir = "C:\Users\nbdor\Documents\Projects\autonomi"
$antdDir = "C:\Users\nbdor\Documents\Projects\ant-sdk\antd"
$logFile = "$env:TEMP\evm-testnet.log"

# Clean up old log
if (Test-Path $logFile) { Remove-Item $logFile }

Write-Host ""
Write-Host "=== antd Local Test Environment ===" -ForegroundColor Cyan
Write-Host ""

# 1. Start EVM testnet
Write-Host "[1/4] Starting EVM testnet..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-NoExit", "-Command", "`$Host.UI.RawUI.WindowTitle='EVM Testnet'; cd '$autonomiDir'; cmd /c 'cargo run --bin evm-testnet 2>&1' | Tee-Object -FilePath '$logFile'"

# 2. Wait for log file to exist, then wait for secret key
Write-Host "       Waiting for secret key..." -ForegroundColor Gray
while (-not (Test-Path $logFile)) {
    Start-Sleep -Seconds 2
}
do {
    Start-Sleep -Seconds 2
    $match = Select-String -Path $logFile -Pattern 'SECRET_KEY=(.+)' -ErrorAction SilentlyContinue
} while (-not $match)

$walletKey = $match.Matches[0].Groups[1].Value.Trim()
Write-Host "       Got wallet key: $($walletKey.Substring(0,10))..." -ForegroundColor Green

# 3. Start local network
Write-Host "[2/4] Starting local Autonomi network..." -ForegroundColor Yellow

# Delete old bootstrap cache BEFORE starting network so we only find fresh peers
$cacheFile = "$env:APPDATA\autonomi\bootstrap_cache\version_1\bootstrap_cache_local_1_1.0.json"
if (Test-Path $cacheFile) {
    Remove-Item $cacheFile -Force
    Write-Host "       Cleared old bootstrap cache" -ForegroundColor Gray
}

Start-Process powershell -ArgumentList "-NoExit", "-Command", "`$Host.UI.RawUI.WindowTitle='Local Network'; cd '$autonomiDir'; cmd /c 'cargo run --release --bin antctl -- local run --build --clean --rewards-address 0xd10A556E6A5111b5D4Dd5Ae06761d41F6CE1D499 2>&1'"

Write-Host "       Waiting for network (this may take a while with --build)..." -ForegroundColor Gray
$peerAddr = $null
for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Seconds 3
    if (Test-Path $cacheFile) {
        try {
            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
            if ($cache.peers.Count -gt 0) {
                # peers is an array of [peer_id, [multiaddr, ...]] pairs
                $peerAddr = $cache.peers[0][1][0]
                break
            }
        } catch {}
    }
}
if (-not $peerAddr) {
    Write-Host "       Could not find local peers in bootstrap cache!" -ForegroundColor Red
    exit 1
}
Write-Host "       Found peer: $($peerAddr.Substring(0,40))..." -ForegroundColor Green

# 4. Start antd
Write-Host "[3/4] Starting antd..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-NoExit", "-Command", "`$Host.UI.RawUI.WindowTitle='antd'; cd '$antdDir'; `$env:AUTONOMI_WALLET_KEY='$walletKey'; `$env:ANT_PEERS='$peerAddr'; cmd /c 'cargo run -- --network local 2>&1'"

# 5. Wait for antd health
Write-Host "[4/4] Waiting for antd to be ready..." -ForegroundColor Yellow
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 3
    try {
        $health = Invoke-RestMethod http://localhost:8080/health -ErrorAction SilentlyContinue
        if ($health.status -eq "ok") {
            $ready = $true
            break
        }
    } catch {}
}

Write-Host ""
if ($ready) {
    Write-Host "=== Ready! ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "  REST:  http://localhost:8080" -ForegroundColor White
    Write-Host "  gRPC:  localhost:50051" -ForegroundColor White
    Write-Host "  Key:   $($walletKey.Substring(0,10))..." -ForegroundColor White
    Write-Host ""
    Write-Host "Quick test:" -ForegroundColor Gray
    Write-Host "  Invoke-RestMethod http://localhost:8080/health" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To tear down:" -ForegroundColor Gray
    Write-Host "  cd $autonomiDir" -ForegroundColor Gray
    Write-Host "  cargo run --release --bin antctl -- local kill" -ForegroundColor Gray
} else {
    Write-Host "=== antd did not respond within timeout ===" -ForegroundColor Red
    Write-Host "Check the antd terminal window for errors." -ForegroundColor Gray
}
