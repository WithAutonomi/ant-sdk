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
Write-Host "[01/10] Health Check" -ForegroundColor Yellow

$health = Api-Get "/health"
Assert-Eq "status is ok" "ok" $health.status
Assert-NotEmpty "network is set" $health.network
Write-Host "       Network: $($health.network)" -ForegroundColor Gray

# ══════════════════════════════════════════════════════════════════════
# Test 02: Public Data - store, cost estimate, retrieve, round-trip
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[02/10] Public Data" -ForegroundColor Yellow

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
Write-Host "[03/10] Chunks" -ForegroundColor Yellow

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
Write-Host "[04/10] Files" -ForegroundColor Yellow

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
# Test 05: Pointers - create, read, exists, update
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[05/10] Pointers" -ForegroundColor Yellow

$ptrKey = RandomSecretKey

# Store two data versions
$v1B64 = B64Encode "version 1"
$v2B64 = B64Encode "version 2"

$v1Resp = Api-Post "/v1/data/public" "{`"data`": `"$v1B64`"}"
$v2Resp = Api-Post "/v1/data/public" "{`"data`": `"$v2B64`"}"

# Create pointer to v1
$ptrBody = "{`"owner_secret_key`": `"$ptrKey`", `"target`": {`"kind`": `"chunk`", `"address`": `"$($v1Resp.address)`"}}"
$ptrCreate = Api-Post "/v1/pointers" $ptrBody
Assert-NotEmpty "pointer address returned" $ptrCreate.address
Assert-NotEmpty "pointer cost returned" $ptrCreate.cost

# Read
$ptrGet = Api-Get "/v1/pointers/$($ptrCreate.address)"
Assert-Eq "pointer target is v1" $v1Resp.address $ptrGet.target.address
Assert-Eq "pointer kind is chunk" "chunk" $ptrGet.target.kind
Assert-NotEmpty "pointer counter returned" "$($ptrGet.counter)"

# Check existence (HEAD)
$headStatus = Api-Head "/v1/pointers/$($ptrCreate.address)"
Assert-Status "pointer exists (HEAD)" 200 $headStatus

# Update to v2
$updBody = "{`"owner_secret_key`": `"$ptrKey`", `"target`": {`"kind`": `"chunk`", `"address`": `"$($v2Resp.address)`"}}"
Api-Put "/v1/pointers/$ptrKey" $updBody | Out-Null

# Read again
$ptrGet2 = Api-Get "/v1/pointers/$($ptrCreate.address)"
Assert-Eq "pointer now targets v2" $v2Resp.address $ptrGet2.target.address

# ══════════════════════════════════════════════════════════════════════
# Test 06: Scratchpads - create, read, exists, update
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[06/10] Scratchpads" -ForegroundColor Yellow

$padKey = RandomSecretKey
$padDataV1 = B64Encode "scratchpad v1 data"
$padDataV2 = B64Encode "scratchpad v2 data"

# Create
$padBody = "{`"owner_secret_key`": `"$padKey`", `"content_type`": 1, `"data`": `"$padDataV1`"}"
$padCreate = Api-Post "/v1/scratchpads" $padBody
Assert-NotEmpty "scratchpad address returned" $padCreate.address
Assert-NotEmpty "scratchpad cost returned" $padCreate.cost

# Read
$padGet = Api-Get "/v1/scratchpads/$($padCreate.address)"
Assert-NotEmpty "scratchpad counter returned" "$($padGet.counter)"
Assert-NotEmpty "scratchpad data_encoding returned" "$($padGet.data_encoding)"

# Check existence (HEAD)
$padHeadStatus = Api-Head "/v1/scratchpads/$($padCreate.address)"
Assert-Status "scratchpad exists (HEAD)" 200 $padHeadStatus

# Update
$padUpdBody = "{`"owner_secret_key`": `"$padKey`", `"content_type`": 1, `"data`": `"$padDataV2`"}"
Api-Put "/v1/scratchpads/$padKey" $padUpdBody | Out-Null

# Read again
$padGet2 = Api-Get "/v1/scratchpads/$($padCreate.address)"
Assert-NotEmpty "scratchpad counter after update" "$($padGet2.counter)"
Write-Host "       Counter: $($padGet.counter) -> $($padGet2.counter)" -ForegroundColor Gray

# ══════════════════════════════════════════════════════════════════════
# Test 07: Graph Entries - create, read, exists, cost
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[07/10] Graph Entries" -ForegroundColor Yellow

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
# Test 08: Registers - create, read, update
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[08/10] Registers" -ForegroundColor Yellow

$regKey = RandomSecretKey
$regInitial = "0" * 64  # 32 zero bytes
$regNewValue = RandomHex 32

# Create
$regBody = "{`"owner_secret_key`": `"$regKey`", `"initial_value`": `"$regInitial`"}"
$regCreate = Api-Post "/v1/registers" $regBody
Assert-NotEmpty "register address returned" $regCreate.address
Assert-NotEmpty "register cost returned" $regCreate.cost

# Read
$regGet = Api-Get "/v1/registers/$($regCreate.address)"
Assert-Eq "register initial value matches" $regInitial $regGet.value

# Update
$regUpdBody = "{`"owner_secret_key`": `"$regKey`", `"new_value`": `"$regNewValue`"}"
$regUpd = Api-Put "/v1/registers/$regKey" $regUpdBody
Assert-NotEmpty "register update cost returned" $regUpd.cost

# Read again
$regGet2 = Api-Get "/v1/registers/$($regCreate.address)"
Assert-Eq "register updated value matches" $regNewValue $regGet2.value

# ══════════════════════════════════════════════════════════════════════
# Test 09: Vaults - store and retrieve
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[09/10] Vaults" -ForegroundColor Yellow

$vaultKey = RandomSecretKey
$vaultPayload = "Secret vault data that is encrypted"
$vaultB64 = B64Encode $vaultPayload
$vaultContentType = 42

# Store
$vaultBody = "{`"secret_key`": `"$vaultKey`", `"data`": `"$vaultB64`", `"content_type`": $vaultContentType}"
$vaultPut = Api-Post "/v1/vaults" $vaultBody
Assert-NotEmpty "vault store cost returned" $vaultPut.cost

# Retrieve
$vaultGet = Api-Get "/v1/vaults?secret_key=$vaultKey"
$vaultGotText = B64Decode $vaultGet.data
Assert-Eq "vault data round-trip matches" $vaultPayload $vaultGotText
Assert-Eq "vault content_type matches" "$vaultContentType" "$($vaultGet.content_type)"

# ══════════════════════════════════════════════════════════════════════
# Test 10: Private Data - store and retrieve
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "[10/10] Private Data" -ForegroundColor Yellow

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
