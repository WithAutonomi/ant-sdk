## Start a local ant devnet + antd gateway for testing.
##
## Prerequisites:
##   - Rust toolchain (cargo)
##   - ant-node repo cloned as sibling: ../ant-node
##     (or set $env:ANT_NODE_DIR)
##
## Usage:
##   .\scripts\start-local.ps1
##
## Tear down:
##   .\scripts\kill-local.ps1

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdkRoot = (Resolve-Path "$scriptDir\..").Path
$antdDir = "$sdkRoot\antd"
$manifestFile = "$env:TEMP\devnet-manifest.json"
$devnetLog = "$env:TEMP\ant-devnet.log"
$antdLog = "$env:TEMP\antd.log"

# Resolve ant-node directory
if ($env:ANT_NODE_DIR) {
    $antNodeDir = $env:ANT_NODE_DIR
} else {
    $candidate = "$sdkRoot\..\ant-node"
    if (Test-Path "$candidate\Cargo.toml") {
        $antNodeDir = (Resolve-Path $candidate).Path
    } else {
        Write-Host "ERROR: Cannot find ant-node repo." -ForegroundColor Red
        Write-Host ""
        Write-Host "Clone it as a sibling to ant-sdk:" -ForegroundColor Gray
        Write-Host "  cd $(Split-Path $sdkRoot)" -ForegroundColor Gray
        Write-Host "  git clone https://github.com/WithAutonomi/ant-node.git" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Or set `$env:ANT_NODE_DIR to its location." -ForegroundColor Gray
        exit 1
    }
}

# Clean up old files
foreach ($f in @($manifestFile, $devnetLog, $antdLog)) {
    if (Test-Path $f) { Remove-Item $f -Force }
}

Write-Host ""
Write-Host "=== antd Local Test Environment ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "  SDK:     $sdkRoot" -ForegroundColor Gray
Write-Host "  Node:    $antNodeDir" -ForegroundColor Gray
Write-Host ""

# ── 1. Start ant devnet ──
Write-Host "[1/3] Starting ant devnet (25 nodes + EVM)..." -ForegroundColor Yellow
$devnetProc = Start-Process -PassThru -FilePath "cargo" `
    -ArgumentList "run", "--release", "--bin", "ant-devnet", "--", "--preset", "default", "--enable-evm", "--manifest", $manifestFile `
    -WorkingDirectory $antNodeDir `
    -RedirectStandardOutput $devnetLog `
    -RedirectStandardError "$devnetLog.err" `
    -WindowStyle Hidden
Write-Host "       PID $($devnetProc.Id)" -ForegroundColor Gray

# ── 2. Wait for manifest ──
Write-Host "       Waiting for devnet (first build may take several minutes)..." -ForegroundColor Gray
$manifest = $null
for ($i = 0; $i -lt 180; $i++) {
    Start-Sleep -Seconds 2
    if (Test-Path $manifestFile) {
        try {
            $manifest = Get-Content $manifestFile -Raw | ConvertFrom-Json
            if ($manifest.bootstrap.Count -gt 0 -and $manifest.evm) { break }
        } catch {}
        $manifest = $null
    }
}

if (-not $manifest) {
    Write-Host "       Timed out waiting for devnet manifest!" -ForegroundColor Red
    Write-Host "       Check log: $devnetLog" -ForegroundColor Gray
    if (Test-Path "$devnetLog.err") {
        Write-Host "       Errors:" -ForegroundColor Gray
        Get-Content "$devnetLog.err" -Tail 5 | ForEach-Object { Write-Host "         $_" -ForegroundColor Gray }
    }
    exit 1
}

$bootstrapPeers = ($manifest.bootstrap -join ",")
$walletKey = $manifest.evm.wallet_private_key -replace '^0x', ''
$evmRpcUrl = $manifest.evm.rpc_url
$evmTokenAddr = $manifest.evm.payment_token_address
$evmPaymentsAddr = $manifest.evm.data_payments_address

Write-Host "       Devnet ready: $($manifest.node_count) nodes, base port $($manifest.base_port)" -ForegroundColor Green
Write-Host "       EVM:   $evmRpcUrl" -ForegroundColor Green

# ── 3. Start antd ──
Write-Host "[2/3] Starting antd..." -ForegroundColor Yellow
$antdEnv = @{
    ANTD_PEERS                 = $bootstrapPeers
    AUTONOMI_WALLET_KEY        = $walletKey
    EVM_RPC_URL                = $evmRpcUrl
    EVM_PAYMENT_TOKEN_ADDRESS  = $evmTokenAddr
    EVM_DATA_PAYMENTS_ADDRESS  = $evmPaymentsAddr
}
# Merge with current environment
$mergedEnv = [System.Collections.Generic.Dictionary[string,string]]::new()
foreach ($entry in [System.Environment]::GetEnvironmentVariables().GetEnumerator()) {
    $mergedEnv[$entry.Key] = $entry.Value
}
foreach ($entry in $antdEnv.GetEnumerator()) {
    $mergedEnv[$entry.Key] = $entry.Value
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "cargo"
$psi.Arguments = "run -- --network local"
$psi.WorkingDirectory = $antdDir
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
foreach ($entry in $mergedEnv.GetEnumerator()) {
    $psi.Environment[$entry.Key] = $entry.Value
}

$antdProcess = [System.Diagnostics.Process]::Start($psi)
# Drain stdout/stderr to log file asynchronously
$antdProcess.BeginOutputReadLine()
$antdProcess.BeginErrorReadLine()
Register-ObjectEvent -InputObject $antdProcess -EventName OutputDataReceived -Action {
    if ($EventArgs.Data) { $EventArgs.Data | Out-File -Append -FilePath "$env:TEMP\antd.log" }
} | Out-Null
Register-ObjectEvent -InputObject $antdProcess -EventName ErrorDataReceived -Action {
    if ($EventArgs.Data) { $EventArgs.Data | Out-File -Append -FilePath "$env:TEMP\antd.log" }
} | Out-Null

Write-Host "       PID $($antdProcess.Id)" -ForegroundColor Gray

# Save PIDs for kill script
@{ devnet_pid = $devnetProc.Id; antd_pid = $antdProcess.Id } | ConvertTo-Json | Set-Content "$env:TEMP\antd-local-pids.json"

# ── 4. Wait for health ──
Write-Host "[3/3] Waiting for antd to be ready..." -ForegroundColor Yellow
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Seconds 3
    try {
        $health = Invoke-RestMethod http://localhost:8082/health -ErrorAction SilentlyContinue
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
    Write-Host "  REST:  http://localhost:8082" -ForegroundColor White
    Write-Host "  gRPC:  localhost:50051" -ForegroundColor White
    Write-Host "  Key:   $($walletKey.Substring(0,10))..." -ForegroundColor White
    Write-Host ""
    Write-Host "Run tests:" -ForegroundColor Gray
    Write-Host "  .\scripts\test-api.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "View logs:" -ForegroundColor Gray
    Write-Host "  Get-Content $antdLog -Tail 20" -ForegroundColor Gray
    Write-Host "  Get-Content $devnetLog -Tail 20" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Tear down:" -ForegroundColor Gray
    Write-Host "  .\scripts\kill-local.ps1" -ForegroundColor Gray
} else {
    Write-Host "=== antd did not respond within timeout ===" -ForegroundColor Red
    Write-Host "Check log: $antdLog" -ForegroundColor Gray
    exit 1
}
