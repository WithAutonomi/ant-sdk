#!/usr/bin/env pwsh
# Run Python SDK integration tests (REST + gRPC)
# Requires a running antd daemon with REST on :8082 and gRPC on :50051

param(
    [string]$RestUrl = "http://localhost:8082",
    [string]$GrpcTarget = "localhost:50051"
)

$ErrorActionPreference = "Continue"
$failed = 0

Write-Host "`n===== Python SDK Integration Tests =====" -ForegroundColor Cyan
Write-Host ""

# --- REST ---
Write-Host "--- Running REST tests ---" -ForegroundColor Yellow
python "$PSScriptRoot\scripts\test_rest.py" $RestUrl
if ($LASTEXITCODE -ne 0) { $failed++ }

Write-Host ""

# --- gRPC ---
Write-Host "--- Running gRPC tests ---" -ForegroundColor Yellow
python "$PSScriptRoot\scripts\test_grpc.py" $GrpcTarget
if ($LASTEXITCODE -ne 0) { $failed++ }

# --- Summary ---
Write-Host ""
if ($failed -eq 0) {
    Write-Host "All test suites passed." -ForegroundColor Green
} else {
    Write-Host "$failed test suite(s) had failures." -ForegroundColor Red
}

exit $failed
