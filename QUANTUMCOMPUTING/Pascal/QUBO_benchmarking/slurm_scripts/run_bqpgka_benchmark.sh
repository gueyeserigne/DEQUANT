#!/bin/bash
# SLURM job: BQPGKA QUBO benchmark via Pulser, run inside the DEQUANT udocker
# container with .venv-pascal.
#
# Runs exactly ONE BQPGKA instance per job, so slurm_logs/ and outputs/ stay
# identically structured. To benchmark several instances, submit several sbatch
# calls via sbatch_sequential.sh.
#
# Usage:
#   sbatch run_bqpgka_benchmark.sh                                        # default: bqpgka20_1.txt, full size
#   sbatch run_bqpgka_benchmark.sh bqpgka30_1.txt                         # explicit instance, full size
#   sbatch run_bqpgka_benchmark.sh --full bqpgka20_1.txt                  # explicit full-size run
#   sbatch run_bqpgka_benchmark.sh --full bqpgka20_1.txt -m "trying alpha=0.9"  # with a note
#
# Log layout: slurm_logs/DD-MM/NNN/<tag>/{run.out,run.err,gpu.csv,gpu.png}
#   Mirrors outputs/DD-MM/NNN/<tag>/*.png exactly — same depth, same NNN, same
#   tag subfolder. IDs (NNN) are a GLOBAL, monotonically increasing counter
#   across all days — same pattern as
#   Patrice_other_experiments/vec2text-mpnet's slurm_train_zero_step_matrix.sh.
#   <tag> is the instance filename without .txt (e.g. bqpgka20_1).
#   #SBATCH --output/--error write to a flat temp path (%j, known at submit time);
#   once the job starts, this script computes the day/NNN/tag folder and moves
#   the temp files into it.
#
#   Grouped batches (sbatch_sequential.sh --group): if $BATCH_RUN_ID is set in
#   the environment, it's used as NNN instead of self-computing a fresh one, so
#   all jobs in the batch share one slurm_logs/DD-MM/NNN/ folder with per-tag
#   subfolders nested inside — instead of each job getting its own NNN. The
#   -m note then lands at DD-MM/NNN/note.txt (batch root) instead of
#   DD-MM/NNN/<tag>/note.txt (per-job).

#SBATCH --job-name=bqpgka_benchmark
#SBATCH --output=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs/slurm_%j.tmp.out
#SBATCH --error=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs/slurm_%j.tmp.err
#SBATCH --time=02:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --gres=gpu:1
# Pinned to achille: heracles (same GPU model, Tesla P100) failed with a CUDA
# init error on 2026-07-02 (job 22220) — untested/unvalidated driver on that
# node. achille is where .venv-pascal/torch+cu126 was built and confirmed
# working. Revisit if achille becomes a bottleneck (queue wait for its 1 GPU).
#SBATCH --nodelist=achille

set -e

# --- Args (parsed before log setup, so the tag is known for naming) -----------
FULL_FLAG=""
NOTE=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --full)
      FULL_FLAG="--full"
      shift
      ;;
    -m)
      NOTE="$2"
      shift 2
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

if [ "${#ARGS[@]}" -gt 1 ]; then
  echo "ERROR: run_bqpgka_benchmark.sh only accepts ONE instance file per job." >&2
  echo "       For multiple instances, submit separate sbatch calls via sbatch_sequential.sh." >&2
  exit 1
fi

FILE="${ARGS[0]:-bqpgka20_1.txt}"
TAG="${FILE%.txt}"

# --- Paths (host-side) --------------------------------------------------------
LOGS_ROOT=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs
ANALYSIS=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/analysis
mkdir -p "$LOGS_ROOT"

# --- Log layout: slurm_logs/DD-MM/NNN/<tag>/ ----------------------------------
TODAY=$(date '+%d-%m')
DAY_DIR="$LOGS_ROOT/$TODAY"
mkdir -p "$DAY_DIR"

# Find highest existing NNN subdir across ALL day-dirs (global counter).
# NNN dirs may now contain a <tag>/ subfolder rather than being flat, so match
# any NNN dir regardless of what's inside it.
if [ -n "$BATCH_RUN_ID" ]; then
  # Grouped batch: reuse the ID the sequencer already reserved, don't compute one.
  NEXT_ID="$BATCH_RUN_ID"
else
  LAST_ID=$(find "$LOGS_ROOT" -maxdepth 2 -mindepth 2 -type d -name "[0-9][0-9][0-9]" | \
            sed 's|.*/||' | sort -n | tail -1)
  NEXT_ID=$(printf "%03d" $(( 10#${LAST_ID:-0} + 1 )))
fi

BATCH_DIR="$DAY_DIR/$NEXT_ID"
LOGS="$BATCH_DIR/$TAG"
mkdir -p "$LOGS"

# Move the SLURM tmp files into the run dir.
mv "$LOGS_ROOT/slurm_${SLURM_JOB_ID}.tmp.out" "$LOGS/run.out" 2>/dev/null || true
mv "$LOGS_ROOT/slurm_${SLURM_JOB_ID}.tmp.err" "$LOGS/run.err" 2>/dev/null || true

if [ -n "$NOTE" ]; then
  if [ -n "$BATCH_RUN_ID" ]; then
    # Grouped batch: one shared note at the batch root (only write once).
    [ -f "$BATCH_DIR/note.txt" ] || echo "$NOTE" > "$BATCH_DIR/note.txt"
  else
    echo "$NOTE" > "$LOGS/note.txt"
  fi
fi

exec >> "$LOGS/run.out" 2>> "$LOGS/run.err"

echo "=================================================="
echo "  Run ID  : $NEXT_ID"
echo "  Job ID  : $SLURM_JOB_ID"
echo "  Node    : $SLURMD_NODENAME"
echo "  File    : $FILE"
echo "  Full    : ${FULL_FLAG:-no (default, still untruncated unless --qubit-sweep used)}"
echo "  Note    : ${NOTE:-(none)}"
echo "  Logs dir: $LOGS"
echo "=================================================="

# --- GPU monitor (runs on the host, polls nvidia-smi every 5s) ---
GPU_LOG="$LOGS/gpu.csv"
python3 $ANALYSIS/gpu_monitor.py --output "$GPU_LOG" --interval 5 &
GPU_MONITOR_PID=$!
trap "kill $GPU_MONITOR_PID 2>/dev/null; echo 'GPU monitor stopped.'" EXIT
echo "[gpu_monitor] PID=$GPU_MONITOR_PID -> $GPU_LOG"

bash /home/data/projets-aps/projet6/udocker_start_scripts/start_dequant_env.sh --run \
  "export BENCHMARK_DAY=$TODAY BENCHMARK_RUN_ID=$NEXT_ID && cd /Quantum_workspace/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/experiments && python benchmark_bqpgka.py --files $FILE $FULL_FLAG"

kill $GPU_MONITOR_PID 2>/dev/null

# plot_gpu.py needs pandas/matplotlib, not guaranteed on the bare host python3 -
# run it through the venv instead, same as the main script.
bash /home/data/projets-aps/projet6/udocker_start_scripts/start_dequant_env.sh --run \
  "python3 $ANALYSIS/plot_gpu.py --csv $GPU_LOG"

echo ""
echo "Done. Logs dir: $LOGS"
