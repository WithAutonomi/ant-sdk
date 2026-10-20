#!/usr/bin/env bash
# Regression tests for nuget-audit.sh, run by security-audit.yml before the
# real audit. A stub `dotnet` returns controlled exit codes and output, so
# every path is exercised without the .NET SDK, including the ones that
# used to pass as clean (restore or listing failures).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/dotnet" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  restore) exit "${STUB_RESTORE_RC:-0}" ;;
  list)
    if [ "${STUB_LIST_OUT:-clean}" = vuln ]; then
      echo "Project \`Fake\` has the following vulnerable packages"
      echo "   > Some.Package   1.0.0   High   https://github.com/advisories/GHSA-xxxx"
    else
      echo "The given project \`Fake\` has no vulnerable packages given the current sources."
    fi
    exit "${STUB_LIST_RC:-0}" ;;
esac
exit 99
STUB
chmod +x "$tmp/dotnet"

fails=0
# run <name> <expected exit> <expected annotation substring or ""> [VAR=value ...]
run() {
  local name="$1" want="$2" grepfor="$3"; shift 3
  local got=0
  env DOTNET="$tmp/dotnet" "$@" bash "$here/nuget-audit.sh" >"$tmp/out" 2>&1 || got=$?
  if [ "$got" -ne "$want" ]; then
    echo "FAIL $name: exit $got, want $want"; cat "$tmp/out"; fails=$((fails + 1)); return
  fi
  if [ -n "$grepfor" ] && ! grep -q -- "$grepfor" "$tmp/out"; then
    echo "FAIL $name: output lacks '$grepfor'"; cat "$tmp/out"; fails=$((fails + 1)); return
  fi
  echo "ok   $name (exit $got)"
}

B=(NUGET_AUDIT_BLOCKING=Fake.csproj NUGET_AUDIT_REPORT_ONLY=)
R=(NUGET_AUDIT_BLOCKING= NUGET_AUDIT_REPORT_ONLY=Example.csproj)

run "blocking: clean"                      0 ""                              "${B[@]}"
run "blocking: vulnerable"                 1 "::error file=Fake.csproj::vulnerable" "${B[@]}" STUB_LIST_OUT=vuln
run "blocking: restore fails"              1 "could not run"                 "${B[@]}" STUB_RESTORE_RC=17
run "blocking: list fails"                 1 "could not run"                 "${B[@]}" STUB_LIST_RC=23
run "blocking: restore and list fail"      1 "could not run"                 "${B[@]}" STUB_RESTORE_RC=17 STUB_LIST_RC=23
run "blocking: list fails, vulns printed"  1 "vulnerable NuGet packages"     "${B[@]}" STUB_LIST_RC=1 STUB_LIST_OUT=vuln
run "report-only: vulnerable warns"        0 "::warning file=Example.csproj::vulnerable" "${R[@]}" STUB_LIST_OUT=vuln
run "report-only: restore fails warns"     0 "::warning file=Example.csproj::NuGet audit could not run" "${R[@]}" STUB_RESTORE_RC=17

if [ "$fails" -ne 0 ]; then
  echo "$fails nuget-audit.sh test(s) failed"
  exit 1
fi
echo "all nuget-audit.sh tests passed"
