#!/bin/bash
# Submit multiple sbatch jobs sequentially: each job is submitted only after the
# previous one has actually STARTED running (not just been queued), so their
# day/NNN log folders (see run_bqpgka_benchmark.sh etc.) get distinct, correctly
# ordered NNN IDs instead of racing to compute the same one.
#
# Usage:
#   bash sbatch_sequential.sh "sbatch run_bqpgka_benchmark.sh --full bqpgka20_1.txt" \
#                              "sbatch run_bqpgka_benchmark.sh --full bqpgka30_1.txt" \
#                              "sbatch run_qaa_qubo_test.sh"
#
# Each argument is a full sbatch command (quoted as one string). Runs are
# submitted in order; this script returns once the LAST job has started
# (it does not wait for jobs to finish, only to start).
#
# Default: each job gets its own slurm_logs/DD-MM/NNN/<tag>/ folder (many NNN
# folders for a big batch).
#
# --group mode: all jobs in this invocation share ONE slurm_logs/DD-MM/NNN/
# folder, with per-job <tag>/ subfolders nested inside instead of each job
# getting its own NNN. A -m note (if any job passes one) lands at the shared
# DD-MM/NNN/note.txt root instead of per-job. Use this when submitting many
# related runs (e.g. a full BQPGKA sweep) to avoid ending up with 100s of
# top-level NNN folders.
#
#   bash sbatch_sequential.sh --group \
#     "sbatch run_bqpgka_benchmark.sh --full bqpgka20_1.txt -m 'full sweep'" \
#     "sbatch run_bqpgka_benchmark.sh --full bqpgka30_1.txt" \
#     "sbatch run_bqpgka_benchmark.sh --full bqpgka40_1.txt"

LOGS_ROOT=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs
POLL_INTERVAL=5   # seconds between squeue checks

GROUP=0
if [ "$1" = "--group" ]; then
    GROUP=1
    shift
fi

if [ "$GROUP" = "1" ]; then
    TODAY=$(date '+%d-%m')
    mkdir -p "$LOGS_ROOT/$TODAY"
    LAST_ID=$(find "$LOGS_ROOT" -maxdepth 2 -mindepth 2 -type d -name "[0-9][0-9][0-9]" | \
              sed 's|.*/||' | sort -n | tail -1)
    export BATCH_RUN_ID=$(printf "%03d" $(( 10#${LAST_ID:-0} + 1 )))
    echo "=== Group mode: all jobs will share slurm_logs/$TODAY/$BATCH_RUN_ID/ ==="
fi

wait_until_running() {
    local jobid="$1"
    while true; do
        state=$(squeue -j "$jobid" -h -o '%T' 2>/dev/null)
        if [ -z "$state" ]; then
            # Job no longer in queue -> either finished already or failed to start.
            echo "  [job $jobid] no longer in queue (finished or failed) — proceeding"
            return
        fi
        if [ "$state" = "RUNNING" ]; then
            echo "  [job $jobid] now RUNNING"
            return
        fi
        echo "  [job $jobid] state=$state, waiting..."
        sleep "$POLL_INTERVAL"
    done
}

for cmd in "$@"; do
    echo "=== Submitting: $cmd ==="
    output=$(eval "$cmd")
    echo "$output"
    jobid=$(echo "$output" | grep -oE '[0-9]+$')
    if [ -z "$jobid" ]; then
        echo "  ERROR: could not parse job ID from sbatch output, skipping wait" >&2
        continue
    fi
    wait_until_running "$jobid"
done

echo "All jobs submitted."
