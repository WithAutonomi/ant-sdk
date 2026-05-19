#!/usr/bin/env bash
# Parallel N-worker sweep: runs `ant dev example all -l <lang>` across all 15 SDKs.
# Workers pull from a shared queue (no batch barriers). LPT-sorted so the
# heaviest builds start first and the light jobs fill the tail.
#
# Env knobs:
#   WORKERS  number of parallel workers (default 3)
#   ANT      path to the `ant` CLI (default: resolved via $PATH)
set -uo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.."

RUN_DIR=.full-stack-sweep-results
WORKERS=${WORKERS:-3}
ANT=${ANT:-ant}
rm -rf "$RUN_DIR" && mkdir -p "$RUN_DIR"

QUEUE=(swift kotlin java rust cpp csharp go dart php ruby python js lua elixir zig)

run_one() {
  local L=$1
  local T0=$(date +%s)
  "$ANT" dev example all -l "$L" > "$RUN_DIR/$L.log" 2>&1
  local RC=$?
  local T1=$(date +%s)
  echo "$L $RC $((T1 - T0))" > "$RUN_DIR/.${L}.exit"
  echo "[$(date -u +%H:%M:%S)]   $L done: rc=$RC ($((T1 - T0))s)" >> "$RUN_DIR/run.log"
}
export ANT RUN_DIR
export -f run_one

RUN_START=$(date +%s)
echo "[$(date -u +%H:%M:%S)] === FULL-STACK SWEEP ($WORKERS workers, ${#QUEUE[@]} SDKs, LPT-sorted) ===" | tee -a "$RUN_DIR/run.log"

printf "%s\n" "${QUEUE[@]}" | xargs -P"$WORKERS" -I{} bash -c "run_one \"\$1\"" _ {}

RUN_END=$(date +%s)
echo "" | tee -a "$RUN_DIR/run.log"
echo "=== SUMMARY (wall: $((RUN_END - RUN_START))s) ===" | tee -a "$RUN_DIR/run.log"

declare -A RESULT SECS
PASSES=0; FAILS=0
for L in "${QUEUE[@]}"; do
  if [ -f "$RUN_DIR/.${L}.exit" ]; then
    read NAME RC T < "$RUN_DIR/.${L}.exit"
    SECS[$L]=$T
    if [ "$RC" -eq 0 ]; then RESULT[$L]="PASS"; PASSES=$((PASSES+1)); else RESULT[$L]="FAIL($RC)"; FAILS=$((FAILS+1)); fi
  else
    RESULT[$L]="MISSING"; SECS[$L]="?"; FAILS=$((FAILS+1))
  fi
done
for L in python go js rust cpp ruby php elixir lua zig dart csharp swift java kotlin; do
  printf "  %-8s %-12s %ss\n" "$L" "${RESULT[$L]}" "${SECS[$L]}" | tee -a "$RUN_DIR/run.log"
done

[ "$FAILS" -eq 0 ]
