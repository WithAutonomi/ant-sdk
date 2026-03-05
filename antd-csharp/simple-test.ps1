#!/usr/bin/env pwsh
# Run C# SDK integration tests (REST + gRPC)
# Requires a running antd daemon with REST on :8080 and gRPC on :50051

param(
    [string]$RestEndpoint = "http://localhost:8080",
    [string]$GrpcEndpoint = "http://localhost:50051"
)

$ErrorActionPreference = "Continue"
$failed = 0
$testProject = "$PSScriptRoot\Antd.Sdk.Tests"

Write-Host "`n===== C# SDK Integration Tests =====" -ForegroundColor Cyan
Write-Host ""

# --- REST ---
Write-Host "--- Running REST tests ---" -ForegroundColor Yellow
dotnet run --project $testProject -- --transport rest --endpoint $RestEndpoint
if ($LASTEXITCODE -ne 0) { $failed++ }

Write-Host ""

# --- gRPC ---
Write-Host "--- Running gRPC tests ---" -ForegroundColor Yellow
dotnet run --project $testProject -- --transport grpc --endpoint $GrpcEndpoint
if ($LASTEXITCODE -ne 0) { $failed++ }

# --- Summary ---
Write-Host ""
if ($failed -eq 0) {
    Write-Host "All test suites passed." -ForegroundColor Green
} else {
    Write-Host "$failed test suite(s) had failures." -ForegroundColor Red
}

exit $failed
