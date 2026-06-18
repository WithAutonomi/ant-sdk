<#
.SYNOPSIS
  Build (and optionally sign) the antd Windows MSI.

.DESCRIPTION
  Adapted from maidsafe/autonomi build-windows-msi.yml. Signs antd.exe FIRST so
  the signed binary is embedded in the MSI, builds the MSI with WiX v5 (x64),
  then signs the MSI. Signing uses DigiCert Software Trust Manager (smctl /
  Azure Trusted Signing) and is skipped with a warning if smctl is unavailable
  or SM_KEYPAIR_ALIAS is unset — the CI job is responsible for installing and
  authenticating smctl (digicert/ssm-code-signing action) before calling this.

.PARAMETER BinDir
  Directory containing the built antd.exe (passed to WiX as ArtifactsDir).

.PARAMETER Version
  Product version (X.Y.Z). Defaults to the version in antd/Cargo.toml.

.PARAMETER OutDir
  Output directory for the MSI. Defaults to .\dist.

.EXAMPLE
  ./build-msi.ps1 -BinDir artifacts\x86_64-pc-windows-msvc\release
#>
param(
    [Parameter(Mandatory = $true)] [string] $BinDir,
    [string] $Version,
    [string] $OutDir = (Join-Path $PSScriptRoot "dist")
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptDir "..\..")).Path

# Fixed asset name (keep in sync with installers/common/metadata.env).
$AssetName = "antd-windows-x64-setup.msi"
$TaskName = "Autonomi antd"

if (-not $Version) {
    $cargo = Get-Content (Join-Path $repoRoot "antd\Cargo.toml")
    $Version = ($cargo | Select-String '^version\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
}
Write-Host "antd MSI build — version $Version"

# Windows Installer ProductVersion must be numeric (major.minor.build), so strip
# any SemVer pre-release/build suffix (e.g. 0.10.1-rc.1 -> 0.10.1). Only the
# first three fields affect MSI upgrade logic, so RC builds share an MSI version
# — fine for a test channel (the asset filename is fixed regardless of version).
$msiVersion = ($Version -split '[-+]')[0]
if ($msiVersion -ne $Version) {
    Write-Host "Sanitized MSI ProductVersion: $Version -> $msiVersion"
}

$artifactsPath = (Resolve-Path $BinDir).Path
$antdExe = Join-Path $artifactsPath "antd.exe"
if (-not (Test-Path $antdExe)) { Write-Error "antd.exe not found in $artifactsPath" }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$outputMsi = Join-Path $OutDir $AssetName

function Test-Smctl {
    return (Get-Command smctl -ErrorAction SilentlyContinue) -and $env:SM_KEYPAIR_ALIAS
}

function Invoke-Sign([string] $Path) {
    if (Test-Smctl) {
        Write-Host "Signing $Path"
        # smctl may print "signCommand ... FAILED" yet still exit 0, so don't
        # trust the exit code alone — verify the resulting signature is Valid and
        # fail hard otherwise (never silently ship an unsigned artifact).
        & smctl sign --keypair-alias "$env:SM_KEYPAIR_ALIAS" --input "$Path"
        $sig = Get-AuthenticodeSignature $Path
        Write-Host "  signature status: $($sig.Status)"
        if ($LASTEXITCODE -ne 0 -or $sig.Status -ne 'Valid') {
            Write-Error "Signing did not produce a valid signature for $Path (exit=$LASTEXITCODE, status=$($sig.Status))"
        }
    } else {
        Write-Warning "smctl unavailable or SM_KEYPAIR_ALIAS unset — NOT signing $Path"
    }
}

# 1) Sign antd.exe before embedding it in the MSI.
Invoke-Sign $antdExe

# 2) Install WiX v5 + UI extension (idempotent).
Write-Host "Ensuring WiX v5 toolset is installed..."
dotnet tool install --global wix --version 5.0.2 2>$null | Out-Null
wix extension add WixToolset.UI.wixext/5.0.2 2>$null | Out-Null

# 3) Build the MSI (x64 so ProgramFiles64Folder => C:\Program Files).
$wxsFile = Join-Path $scriptDir "antd.wxs"
Write-Host "Building MSI -> $outputMsi"
wix build `
    -arch x64 `
    -d ProductVersion=$msiVersion `
    -d ArtifactsDir=$artifactsPath `
    -ext WixToolset.UI.wixext `
    -o $outputMsi `
    $wxsFile
if ($LASTEXITCODE -ne 0) { Write-Error "WiX build failed" }

# 4) Sign the MSI.
Invoke-Sign $outputMsi

Write-Host "Done: $outputMsi"
Get-Item $outputMsi | Format-List Name, Length
