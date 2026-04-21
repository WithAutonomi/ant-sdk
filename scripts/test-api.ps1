## REST API integration tests using only Invoke-RestMethod / Invoke-WebRequest.
## Zero dependencies beyond PowerShell.
##
## Prerequisites:
##   Run .\scripts\start-local.ps1 first, wait for "=== Ready! ===".
##
## Usage:
##   .\scripts\test-api.ps1

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

function Assert-NotEmpty([string]$label, $value) {
    $text = if ($null -eq $value) { "" } else { [string]$value }
    if ($text -and $text -ne "null" -and $text -ne "") {
        Write-Host "  PASS $label" -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "  FAIL $label (empty or null)" -ForegroundColor Red
        $script:Fail++
    }
}

function Skip-Test([string]$label, [string]$reason = "not available") {
    Write-Host "  SKIP $label ($reason)" -ForegroundColor DarkYellow
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

function Api-PostStatus([string]$path, [string]$jsonBody) {
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
        $resp = Invoke-WebRequest -Uri "$BaseUrl$path" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -UseBasicParsing
        return $resp.StatusCode
    } catch {
        if ($_.Exception.Response) {
            return [int]$_.Exception.Response.StatusCode
        }
        $body = Get-ErrorBody $_
        $detail = if ($body) { " -- $body" } else { "" }
        Write-Host "       ERROR POST $path - $($_.Exception.Message)$detail" -ForegroundColor Gray
        return 0
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
# Test 02: Public Data — put + get roundtrip
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[02/06] Public Data" -ForegroundColor Yellow

$dataPayload = "Public data payload for roundtrip"
$dataB64 = B64Encode $dataPayload

$dataPut = Api-Post "/v1/data/public" "{`"data`": `"$dataB64`"}"
if ($dataPut -and $dataPut.address) {
    Assert-NotEmpty "data address returned" $dataPut.address
    Assert-NotEmpty "chunks_stored returned" $dataPut.chunks_stored
    Assert-NotEmpty "payment_mode_used returned" $dataPut.payment_mode_used
    Write-Host "       Address: $($dataPut.address.Substring(0, [Math]::Min(16, $dataPut.address.Length)))...  Chunks: $($dataPut.chunks_stored)  Mode: $($dataPut.payment_mode_used)" -ForegroundColor Gray

    $dataGet = Api-Get "/v1/data/public/$($dataPut.address)"
    $dataGot = B64Decode $dataGet.data
    Assert-Eq "data round-trip matches" $dataPayload $dataGot
} else {
    Write-Host "  FAIL data PUT failed (see error above)" -ForegroundColor Red
    $Fail += 4
}

# ══════════════════════════════════════════════════════════════════════
# Test 03: Raw Chunks — store and retrieve
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[03/06] Chunks" -ForegroundColor Yellow

$chunkPayload = "Raw chunk content for direct storage"
$chunkB64 = B64Encode $chunkPayload

$chunkPut = Api-Post "/v1/chunks" "{`"data`": `"$chunkB64`"}"
if ($chunkPut -and $chunkPut.address) {
    Assert-NotEmpty "chunk address returned" $chunkPut.address
    Assert-NotEmpty "chunk cost returned" $chunkPut.cost
    Write-Host "       Address: $($chunkPut.address.Substring(0, [Math]::Min(16, $chunkPut.address.Length)))...  Cost: $($chunkPut.cost)" -ForegroundColor Gray

    $chunkGet = Api-Get "/v1/chunks/$($chunkPut.address)"
    $chunkGot = B64Decode $chunkGet.data
    Assert-Eq "chunk round-trip matches" $chunkPayload $chunkGot
} else {
    Write-Host "  FAIL chunk PUT failed (see error above)" -ForegroundColor Red
    $Fail += 3
}

# ══════════════════════════════════════════════════════════════════════
# Test 04: Files — upload + download roundtrip
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[04/06] Files" -ForegroundColor Yellow

$filePayload = "File contents for upload roundtrip " + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$tmpSrc = Join-Path $env:TEMP ("antd_test_src_" + [Guid]::NewGuid().ToString("N") + ".txt")
$tmpDst = $tmpSrc + ".downloaded"
[System.IO.File]::WriteAllText($tmpSrc, $filePayload)

$srcJson = $tmpSrc.Replace('\', '\\')
$dstJson = $tmpDst.Replace('\', '\\')

$filePut = Api-Post "/v1/files/upload/public" "{`"path`": `"$srcJson`"}"
if ($filePut -and $filePut.address) {
    Assert-NotEmpty "file address returned" $filePut.address
    Assert-NotEmpty "storage_cost_atto returned" $filePut.storage_cost_atto
    Assert-NotEmpty "gas_cost_wei returned" $filePut.gas_cost_wei
    Assert-NotEmpty "chunks_stored returned" $filePut.chunks_stored
    Assert-NotEmpty "payment_mode_used returned" $filePut.payment_mode_used
    Write-Host "       Address: $($filePut.address.Substring(0, [Math]::Min(16, $filePut.address.Length)))...  Storage: $($filePut.storage_cost_atto)  Gas: $($filePut.gas_cost_wei)  Chunks: $($filePut.chunks_stored)" -ForegroundColor Gray

    $dlStatus = Api-PostStatus "/v1/files/download/public" "{`"address`": `"$($filePut.address)`", `"dest_path`": `"$dstJson`"}"
    Assert-Eq "file download status 200" "200" ([string]$dlStatus)

    if (Test-Path $tmpDst) {
        $fileGot = [System.IO.File]::ReadAllText($tmpDst)
        Assert-Eq "file round-trip matches" $filePayload $fileGot
    } else {
        Write-Host "  FAIL downloaded file not written to $tmpDst" -ForegroundColor Red
        $Fail++
    }
} else {
    Write-Host "  FAIL file upload failed (see error above)" -ForegroundColor Red
    $Fail += 6
}

Remove-Item -Force -ErrorAction SilentlyContinue $tmpSrc, $tmpDst

# ══════════════════════════════════════════════════════════════════════
# Test 05: Private Data — put + get roundtrip
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[05/06] Private Data" -ForegroundColor Yellow

$privPayload = "Encrypted secret payload"
$privB64 = B64Encode $privPayload

$privPut = Api-Post "/v1/data/private" "{`"data`": `"$privB64`"}"
if ($privPut -and $privPut.data_map) {
    Assert-NotEmpty "data_map returned" $privPut.data_map
    Assert-NotEmpty "chunks_stored returned" $privPut.chunks_stored
    Assert-NotEmpty "payment_mode_used returned" $privPut.payment_mode_used
    Write-Host "       DataMap: $($privPut.data_map.Substring(0, [Math]::Min(16, $privPut.data_map.Length)))...  Chunks: $($privPut.chunks_stored)  Mode: $($privPut.payment_mode_used)" -ForegroundColor Gray

    $encodedMap = [System.Uri]::EscapeDataString($privPut.data_map)
    $privGet = Api-Get "/v1/data/private?data_map=$encodedMap"
    $privGot = B64Decode $privGet.data
    Assert-Eq "private round-trip matches" $privPayload $privGot
} else {
    Write-Host "  FAIL private PUT failed (see error above)" -ForegroundColor Red
    $Fail += 4
}

# ══════════════════════════════════════════════════════════════════════
# Test 06: Cost estimation (data + file)
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[06/06] Cost estimation" -ForegroundColor Yellow

$costPayload = "Cost estimation payload"
$costB64 = B64Encode $costPayload

$dataCost = Api-Post "/v1/data/cost" "{`"data`": `"$costB64`"}"
if ($dataCost -and $dataCost.cost) {
    Assert-NotEmpty "data cost returned" $dataCost.cost
    Assert-NotEmpty "data file_size returned" $dataCost.file_size
    Assert-NotEmpty "data chunk_count returned" $dataCost.chunk_count
    Assert-NotEmpty "data estimated_gas_cost_wei returned" $dataCost.estimated_gas_cost_wei
    Assert-NotEmpty "data payment_mode returned" $dataCost.payment_mode
    Write-Host "       Cost: $($dataCost.cost)  Size: $($dataCost.file_size)  Chunks: $($dataCost.chunk_count)  Gas: $($dataCost.estimated_gas_cost_wei)  Mode: $($dataCost.payment_mode)" -ForegroundColor Gray
} else {
    Write-Host "  FAIL /v1/data/cost failed (see error above)" -ForegroundColor Red
    $Fail += 5
}

$tmpCost = Join-Path $env:TEMP ("antd_test_cost_" + [Guid]::NewGuid().ToString("N") + ".txt")
[System.IO.File]::WriteAllText($tmpCost, ($costPayload + " extra content for file sampling"))
$costJson = $tmpCost.Replace('\', '\\')

$fileCost = Api-Post "/v1/files/cost" "{`"path`": `"$costJson`", `"is_public`": true}"
if ($fileCost -and $fileCost.cost) {
    Assert-NotEmpty "file cost returned" $fileCost.cost
    Assert-NotEmpty "file file_size returned" $fileCost.file_size
    Assert-NotEmpty "file chunk_count returned" $fileCost.chunk_count
    Assert-NotEmpty "file estimated_gas_cost_wei returned" $fileCost.estimated_gas_cost_wei
    Assert-NotEmpty "file payment_mode returned" $fileCost.payment_mode
    Write-Host "       Cost: $($fileCost.cost)  Size: $($fileCost.file_size)  Chunks: $($fileCost.chunk_count)  Gas: $($fileCost.estimated_gas_cost_wei)  Mode: $($fileCost.payment_mode)" -ForegroundColor Gray
} else {
    Write-Host "  FAIL /v1/files/cost failed (see error above)" -ForegroundColor Red
    $Fail += 5
}

Remove-Item -Force -ErrorAction SilentlyContinue $tmpCost

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
