## REST API integration tests using only Invoke-RestMethod / Invoke-WebRequest.
## Zero dependencies beyond PowerShell.
## Prerequisite: antd daemon running on local testnet.

$ErrorActionPreference = "Continue"

$BaseUrl = if ($env:ANTD_BASE_URL) { $env:ANTD_BASE_URL } else { "http://localhost:8080" }
$Pass = 0
$Fail = 0

# ── Helpers ──

function B64Encode([string]$text) {
    [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($text))
}

function B64Decode([string]$b64) {
    [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
}

function RandomHex([int]$bytes = 32) {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $buf = New-Object byte[] $bytes
    $rng.GetBytes($buf)
    ($buf | ForEach-Object { $_.ToString("x2") }) -join ''
}

function RandomSecretKey() {
    # BLS12-381 secret keys must be < field modulus (~2^255).
    # Zero the first and last bytes so the value fits regardless of endianness.
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $buf = New-Object byte[] 32
    $rng.GetBytes($buf)
    $buf[0]  = 0
    $buf[31] = 0
    ($buf | ForEach-Object { $_.ToString("x2") }) -join ''
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

function Assert-Status([string]$label, [int]$expected, [int]$actual) {
    if ($expected -eq $actual) {
        Write-Host "  PASS $label (HTTP $actual)" -ForegroundColor Green
        $script:Pass++
    } else {
        Write-Host "  FAIL $label (expected HTTP $expected, got $actual)" -ForegroundColor Red
        $script:Fail++
    }
}

# Api helpers - return $null on error so assertions fail gracefully instead of
# spewing unhandled exceptions.  Use -Compress on ConvertTo-Json and send the
# body as a UTF-8 byte array to avoid encoding issues.

function Get-ErrorBody($ex) {
    # Extract the response body from a WebException for better diagnostics.
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

function Api-Put([string]$path, [string]$jsonBody) {
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
        Invoke-RestMethod -Uri "$BaseUrl$path" -Method Put -ContentType "application/json; charset=utf-8" -Body $bytes
    } catch {
        $body = Get-ErrorBody $_
        $detail = if ($body) { " -- $body" } else { "" }
        Write-Host "       ERROR PUT $path - $($_.Exception.Message)$detail" -ForegroundColor Gray
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

function Api-Head([string]$path) {
    try {
        $resp = Invoke-WebRequest -Uri "$BaseUrl$path" -Method Head -UseBasicParsing -ErrorAction Stop
        $resp.StatusCode
    } catch {
        if ($_.Exception.Response) {
            [int]$_.Exception.Response.StatusCode
        } else {
            0
        }
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
# Test 02: Public Data - store, cost estimate, retrieve, round-trip
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[02/06] Public Data" -ForegroundColor Yellow

$dataPayload = "Hello, Autonomi network!"
$dataB64 = B64Encode $dataPayload

# Cost estimate
$costResp = Api-Post "/v1/data/cost" "{`"data`": `"$dataB64`"}"
Assert-NotEmpty "cost estimate returned" $costResp.cost
Write-Host "       Estimated cost: $($costResp.cost) atto tokens" -ForegroundColor Gray

# Store
$putResp = Api-Post "/v1/data/public" "{`"data`": `"$dataB64`"}"
$dataAddr = $putResp.address
$dataCost = $putResp.cost
Assert-NotEmpty "data address returned" $dataAddr
Assert-NotEmpty "data cost returned" $dataCost
Write-Host "       Address: $($dataAddr.Substring(0, [Math]::Min(16, $dataAddr.Length)))..." -ForegroundColor Gray

# Retrieve
$getResp = Api-Get "/v1/data/public/$dataAddr"
$gotText = B64Decode $getResp.data
Assert-Eq "round-trip matches" $dataPayload $gotText

# ══════════════════════════════════════════════════════════════════════
# Test 03: Raw Chunks - store and retrieve
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[03/06] Chunks" -ForegroundColor Yellow

$chunkPayload = "Raw chunk content for direct storage"
$chunkB64 = B64Encode $chunkPayload

# Store
$chunkPut = Api-Post "/v1/chunks" "{`"data`": `"$chunkB64`"}"
Assert-NotEmpty "chunk address returned" $chunkPut.address
Assert-NotEmpty "chunk cost returned" $chunkPut.cost

# Retrieve
$chunkGet = Api-Get "/v1/chunks/$($chunkPut.address)"
$chunkGot = B64Decode $chunkGet.data
Assert-Eq "chunk round-trip matches" $chunkPayload $chunkGot

# ══════════════════════════════════════════════════════════════════════
# Test 04: Files - upload and download
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[04/06] Files" -ForegroundColor Yellow

$srcFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $srcFile -Value "Hello from a file on Autonomi!" -NoNewline

# Escape backslashes in path for JSON
$srcFileJson = $srcFile -replace '\\', '\\'

# Cost estimate
$fileCostResp = Api-Post "/v1/cost/file" "{`"path`": `"$srcFileJson`", `"is_public`": true, `"include_archive`": false}"
Assert-NotEmpty "file cost estimate returned" $fileCostResp.cost

# Upload
$fileUp = Api-Post "/v1/files/upload/public" "{`"path`": `"$srcFileJson`"}"
Assert-NotEmpty "file address returned" $fileUp.address
Assert-NotEmpty "file upload cost returned" $fileUp.cost

# Download
$destFile = "$srcFile.downloaded"
$destFileJson = $destFile -replace '\\', '\\'
Api-Post "/v1/files/download/public" "{`"address`": `"$($fileUp.address)`", `"dest_path`": `"$destFileJson`"}" | Out-Null

if (Test-Path $destFile) {
    $dlContent = Get-Content -Path $destFile -Raw
    Assert-Eq "file content matches" "Hello from a file on Autonomi!" $dlContent
    Remove-Item $destFile -Force
} else {
    Write-Host "  FAIL downloaded file not found" -ForegroundColor Red
    $Fail++
}
Remove-Item $srcFile -Force

# ══════════════════════════════════════════════════════════════════════
# Test 05: Graph Entries - create, read, exists, cost
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[05/06] Graph Entries" -ForegroundColor Yellow

$graphKey = RandomSecretKey
$graphContent = RandomHex 32

# Create root entry - build JSON manually to guarantee empty arrays serialize as []
$graphBody = "{`"owner_secret_key`": `"$graphKey`", `"parents`": [], `"content`": `"$graphContent`", `"descendants`": []}"
$graphCreate = Api-Post "/v1/graph" $graphBody
Assert-NotEmpty "graph entry address returned" $graphCreate.address
Assert-NotEmpty "graph entry cost returned" $graphCreate.cost

# Read
$graphGet = Api-Get "/v1/graph/$($graphCreate.address)"
Assert-NotEmpty "graph entry owner returned" $graphGet.owner
Assert-Eq "graph entry content matches" $graphContent $graphGet.content
Assert-Eq "graph entry has 0 parents" "0" "$($graphGet.parents.Count)"

# Check existence (HEAD)
$graphHeadStatus = Api-Head "/v1/graph/$($graphCreate.address)"
Assert-Status "graph entry exists (HEAD)" 200 $graphHeadStatus

# Cost estimate (uses the owner public key from the GET response)
$graphCostResp = Api-Post "/v1/graph/cost" "{`"public_key`": `"$($graphGet.owner)`"}"
Assert-NotEmpty "graph entry cost estimate returned" $graphCostResp.cost

# ══════════════════════════════════════════════════════════════════════
# Test 06: Private Data - store and retrieve
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[06/06] Private Data" -ForegroundColor Yellow

$privPayload = "This message is encrypted on the network"
$privB64 = B64Encode $privPayload

# Store private
$privPut = Api-Post "/v1/data/private" "{`"data`": `"$privB64`"}"
$dataMap = $privPut.data_map
Assert-NotEmpty "private data map returned" $dataMap
Assert-NotEmpty "private data cost returned" $privPut.cost

# Retrieve and decrypt
$privGet = Api-Get "/v1/data/private?data_map=$dataMap"
$privGotText = B64Decode $privGet.data
Assert-Eq "private data round-trip matches" $privPayload $privGotText

# ══════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
$total = $Pass + $Fail
Write-Host "  $Pass passed, $Fail failed out of $total assertions" -NoNewline
if ($Fail -gt 0) {
    Write-Host "" -ForegroundColor Red
} else {
    Write-Host "" -ForegroundColor Green
}
Write-Host ""

if ($Fail -gt 0) { exit 1 }
