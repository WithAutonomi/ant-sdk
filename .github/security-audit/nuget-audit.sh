#!/usr/bin/env bash
# Used by .github/workflows/security-audit.yml (dotnet-audit job).
#
# Lists vulnerable NuGet packages, transitive included, for each project.
# osv-scanner only sees the direct PackageReferences in a .csproj, so this
# is the transitive check for .NET.
#
# Exit status: 1 if any blocking project has a vulnerable package OR could
# not be audited (restore or listing failed); 0 otherwise. Report-only
# projects (examples) only ever produce warnings.
#
# Every failure is checked explicitly instead of relying on `set -e`: bash
# disables errexit inside a function called from `f || ...`, so a failed
# restore used to fall through to the final grep and pass as clean.
#
# Tests: .github/security-audit/test-nuget-audit.sh (stub dotnet via DOTNET,
# project lists via NUGET_AUDIT_BLOCKING / NUGET_AUDIT_REPORT_ONLY).
set -uo pipefail

DOTNET="${DOTNET:-dotnet}"

blocking=(
  antd-csharp/Antd.Sdk/Antd.Sdk.csproj
  antd-csharp/Antd.Sdk.Tests/Antd.Sdk.Tests.csproj
  ffi/csharp/AntFfi/AntFfi.csproj
  ffi/csharp/AntFfi.Tests/AntFfi.Tests.csproj
)
report_only=(
  antd-csharp/Examples/Examples.csproj
)
if [ -n "${NUGET_AUDIT_BLOCKING+set}" ]; then
  read -r -a blocking <<< "$NUGET_AUDIT_BLOCKING"
fi
if [ -n "${NUGET_AUDIT_REPORT_ONLY+set}" ]; then
  read -r -a report_only <<< "$NUGET_AUDIT_REPORT_ONLY"
fi

out="$(mktemp)"
trap 'rm -f "$out"' EXIT

# 0 = clean, 1 = vulnerable packages found, 2 = the audit could not run.
check() {
  local project="$1" list_rc=0
  if ! "$DOTNET" restore "$project" >/dev/null; then
    echo "dotnet restore failed for $project" >&2
    return 2
  fi
  "$DOTNET" list "$project" package --vulnerable --include-transitive >"$out" || list_rc=$?
  cat "$out"
  if grep -q "has the following vulnerable packages" "$out"; then
    return 1
  fi
  if [ "$list_rc" -ne 0 ]; then
    echo "dotnet list package failed for $project (exit $list_rc)" >&2
    return 2
  fi
  return 0
}

failed=0
for p in ${blocking[@]+"${blocking[@]}"}; do
  echo "::group::$p"
  rc=0
  check "$p" || rc=$?
  echo "::endgroup::"
  case "$rc" in
    0) ;;
    1) echo "::error file=$p::vulnerable NuGet packages"; failed=1 ;;
    *) echo "::error file=$p::NuGet audit could not run (restore or package listing failed)"; failed=1 ;;
  esac
done
for p in ${report_only[@]+"${report_only[@]}"}; do
  echo "::group::$p (report only)"
  rc=0
  check "$p" || rc=$?
  echo "::endgroup::"
  case "$rc" in
    0) ;;
    1) echo "::warning file=$p::vulnerable NuGet packages (examples are report-only)" ;;
    *) echo "::warning file=$p::NuGet audit could not run (examples are report-only)" ;;
  esac
done
exit "$failed"
