## REST API integration tests using only Invoke-RestMethod / Invoke-WebRequest.
## Zero dependencies beyond PowerShell.
##
## Prerequisites:
##   Run .\scripts\start-local.ps1 first, wait for "=== Ready! ===".
##
## Usage:
##   .\scripts\test-api.ps1
##
## Currently tests health + chunks (working with ant-node).
## Data, files, graph, and private data are not yet implemented.

$ErrorActionPreference = "Continue"

$BaseUrl = if ($env:ANTD_BASE_URL) { $env:ANTD_BASE_URL } else { "http://localhost:8082" }
$Pass = 0
$Fail = 0
$Skip = 0

# ── Helpers ──

function B64Encode([string]$text) {
    [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($text))
}

function B64Decode([string]$b64) {
    [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
}

function Assert-Eq([string]$label, [string]$expected, [string]$actual) {
    if ($expected -eq $actual) {
        Write-Host "  PASS $label" -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "  FAIL $label" -ForegroundColor Red
        Write-Host "       expected: $expected" -ForegroundColor Gray
        Write-Host "       actual:   $actual" -ForegroundColor Gray
        $script:Fail++
    }
}

function Assert-NotEmpty([string]$label, [string]$value) {
    if ($value -and $value -ne "null" -and $value -ne "") {
        Write-Host "  PASS $label" -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "  FAIL $label (empty or null)" -ForegroundColor Red
        $script:Fail++
    }
}

function Skip-Test([string]$label) {
    Write-Host "  SKIP $label (not yet implemented for ant-node)" -ForegroundColor DarkYellow
    $script:Skip++
}

function Get-ErrorBody($ex) {
    try {
        $stream = $ex.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $body = $reader.ReadToEnd()
        $reader.Close()
        return $body
    } catch {
        return ""
    }
}

function Api-Post([string]$path, [string]$jsonBody) {
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
        Invoke-RestMethod -Uri "$BaseUrl$path" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes
    } catch {
        $body = Get-ErrorBody $_
        $detail = if ($body) { " -- $body" } else { "" }
        Write-Host "       ERROR POST $path - $($_.Exception.Message)$detail" -ForegroundColor Gray
        $null
    }
}

function Api-Get([string]$path) {
    try {
        Invoke-RestMethod -Uri "$BaseUrl$path" -Method Get
    } catch {
        $body = Get-ErrorBody $_
        $detail = if ($body) { " -- $body" } else { "" }
        Write-Host "       ERROR GET $path - $($_.Exception.Message)$detail" -ForegroundColor Gray
        $null
    }
}

Write-Host ""
Write-Host "=== antd REST API Tests ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl" -ForegroundColor Gray
Write-Host ""

# ══════════════════════════════════════════════════════════════════════
# Test 01: Health Check
# ══════════════════════════════════════════════════════════════════════
Write-Host "[01/06] Health Check" -ForegroundColor Yellow

$health = Api-Get "/health"
Assert-Eq "status is ok" "ok" $health.status
Assert-NotEmpty "network is set" $health.network
Write-Host "       Network: $($health.network)" -ForegroundColor Gray

# ══════════════════════════════════════════════════════════════════════
# Test 02: Public Data (SKIPPED — not yet implemented for ant-node)
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[02/06] Public Data" -ForegroundColor Yellow
Skip-Test "public data put/get/cost"

# ══════════════════════════════════════════════════════════════════════
# Test 03: Raw Chunks - store and retrieve
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[03/06] Chunks" -ForegroundColor Yellow

$chunkPayload = "Raw chunk content for direct storage"
$chunkB64 = B64Encode $chunkPayload

# Store
$chunkPut = Api-Post "/v1/chunks" "{`"data`": `"$chunkB64`"}"
if ($chunkPut -and $chunkPut.address) {
    Assert-NotEmpty "chunk address returned" $chunkPut.address
    Assert-NotEmpty "chunk cost returned" $chunkPut.cost
    Write-Host "       Address: $($chunkPut.address.Substring(0, [Math]::Min(16, $chunkPut.address.Length)))...  Cost: $($chunkPut.cost)" -ForegroundColor Gray

    # Retrieve
    $chunkGet = Api-Get "/v1/chunks/$($chunkPut.address)"
    $chunkGot = B64Decode $chunkGet.data
    Assert-Eq "chunk round-trip matches" $chunkPayload $chunkGot
} else {
    Write-Host "  FAIL chunk PUT failed (see error above)" -ForegroundColor Red
    $Fail += 3
}

# ══════════════════════════════════════════════════════════════════════
# Test 04: Files (SKIPPED — not yet implemented for ant-node)
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[04/06] Files" -ForegroundColor Yellow
Skip-Test "file upload/download/cost"

# ══════════════════════════════════════════════════════════════════════
# Test 05: Graph Entries (SKIPPED — not yet implemented for ant-node)
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[05/06] Graph Entries" -ForegroundColor Yellow
Skip-Test "graph entry put/get/exists/cost"

# ══════════════════════════════════════════════════════════════════════
# Test 06: Private Data (SKIPPED — not yet implemented for ant-node)
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[06/06] Private Data" -ForegroundColor Yellow
Skip-Test "private data put/get"

# ══════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
$total = $Pass + $Fail
Write-Host "  $Pass passed, $Fail failed, $Skip skipped out of $($total + $Skip) tests" -NoNewline
if ($Fail -gt 0) {
    Write-Host "" -ForegroundColor Red
} else {
    Write-Host "" -ForegroundColor Green
}
Write-Host ""

if ($Fail -gt 0) { exit 1 }
