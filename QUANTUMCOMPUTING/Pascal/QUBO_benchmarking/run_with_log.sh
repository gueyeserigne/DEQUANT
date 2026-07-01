#!/bin/bash
# Wraps any command, captures output + exit code + OOM info to a log file.
# Log name format: 001_05-06-2026_23h52m21s_<script_basename>.log
#
# Adapted from Patrice_other_experiments/vec2text-mpnet/my_experiments/scripts/run_with_log.sh
#
# Usage (run from QUBO_benchmarking/):
#   bash run_with_log.sh sbatch my_qubo_job.sh
#   bash run_with_log.sh bash my_qubo_job.sh

LOG_DIR="$(cd "$(dirname "$0")" && pwd)/slurm_logs"
COUNTER_FILE="$LOG_DIR/.run_counter"
mkdir -p "$LOG_DIR"

# Auto-incrementing ID
if [ -f "$COUNTER_FILE" ]; then
    ID=$(cat "$COUNTER_FILE")
    ID=$((ID + 1))
else
    ID=1
fi
printf "%d" "$ID" > "$COUNTER_FILE"

# Format: 001_05-06-2026_23h52m21s_scriptname.log
ID_STR=$(printf "%03d" "$ID")
TIMESTAMP=$(date '+%d-%m-%Y_%Hh%Mm%Ss')
SCRIPT_NAME=$(basename "${!#}" .sh)   # last arg, strip .sh
LOG="$LOG_DIR/${ID_STR}_${TIMESTAMP}_${SCRIPT_NAME}.log"

echo "Logging to $LOG"
echo "Command: $@"

{
    echo "=== START: $(date) ==="
    echo "=== CMD: $@ ==="
    echo "=== Memory before ==="
    free -h
    echo ""

    "$@"
    EXIT=$?

    echo ""
    echo "=== EXIT CODE: $EXIT ==="
    echo "=== Memory after ==="
    free -h
    echo "=== OOM check ==="
    dmesg 2>/dev/null | grep -E "oom|[Kk]ill" | tail -10
    echo "=== END: $(date) ==="
} 2>&1 | tee "$LOG"

echo "Done. Log at $LOG"
