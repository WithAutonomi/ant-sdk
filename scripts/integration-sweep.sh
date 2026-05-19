#!/usr/bin/env bash
# Serial sweep: runs `ant dev example all -l <lang>` across all 15 SDKs in
# sequence, with per-language PASS/FAIL and wall-clock seconds.
#
# Env knobs:
#   ANT  path to the `ant` CLI (default: resolved via $PATH)
set -uo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

RUN_DIR=.integration-results
ANT=${ANT:-ant}
rm -rf "$RUN_DIR" && mkdir -p "$RUN_DIR"

LANGS=(python go js rust cpp ruby php elixir lua zig dart csharp swift java kotlin)
declare -A RESULT
declare -A SECS

for L in "${LANGS[@]}"; do
  echo "[$(date -u +%H:%M:%S)] === $L all ===" | tee -a "$RUN_DIR/run.log"
  T0=$(date +%s)
  "$ANT" dev example all -l "$L" > "$RUN_DIR/$L.log" 2>&1
  RC=$?
  T1=$(date +%s)
  SECS[$L]=$(( T1 - T0 ))
  if [ $RC -eq 0 ]; then RESULT[$L]="PASS"; else RESULT[$L]="FAIL($RC)"; fi
  echo "[$(date -u +%H:%M:%S)] $L: ${RESULT[$L]} (${SECS[$L]}s)" | tee -a "$RUN_DIR/run.log"
done

echo "" | tee -a "$RUN_DIR/run.log"
echo "=== SUMMARY ===" | tee -a "$RUN_DIR/run.log"
for L in "${LANGS[@]}"; do
  printf "  %-8s %-12s %ss\n" "$L" "${RESULT[$L]}" "${SECS[$L]}" | tee -a "$RUN_DIR/run.log"
done
for L in "${LANGS[@]}"; do [[ "${RESULT[$L]}" == PASS ]] || exit 1; done
exit 0
