#!/bin/bash
# SLURM job: BQPGKA GPU timing sweep (10/15/20 qubits) via benchmark_bqpgka.py
# --qubit-sweep, run inside the DEQUANT udocker container with .venv-pascal.
# Also polls GPU memory/utilization every 5s (analysis/gpu_monitor.py) so
# memory-vs-qubit-count can be inspected afterwards with analysis/plot_gpu.py.
#
# Usage:
#   sbatch run_bqpgka_qubit_sweep.sh
#
# Log layout: slurm_logs/DD-MM/NNN/NNN_bqpgka_qubit_sweep.{out,err,gpu.csv,gpu.png}
#   IDs (NNN) are a GLOBAL, monotonically increasing counter across all days —
#   same pattern as run_bqpgka_benchmark.sh / vec2text-mpnet's slurm_train_zero_step_matrix.sh.

#SBATCH --job-name=bqpgka_qubit_sweep
#SBATCH --output=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs/slurm_%j.tmp.out
#SBATCH --error=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs/slurm_%j.tmp.err
#SBATCH --time=24:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --gres=gpu:1

set -e

# --- Paths (host-side) --------------------------------------------------------
LOGS_ROOT=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs
ANALYSIS=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/analysis
mkdir -p "$LOGS_ROOT"

# --- Log layout: slurm_logs/DD-MM/NNN/ ---------------------------------------
TODAY=$(date '+%d-%m')
DAY_DIR="$LOGS_ROOT/$TODAY"
mkdir -p "$DAY_DIR"

LAST_ID=$(find "$LOGS_ROOT" -maxdepth 2 -mindepth 2 -type d -name "[0-9][0-9][0-9]" | \
          sed 's|.*/||' | sort -n | tail -1)
NEXT_ID=$(printf "%03d" $(( 10#${LAST_ID:-0} + 1 )))

BASENAME="${NEXT_ID}_bqpgka_qubit_sweep"
LOGS="$DAY_DIR/$NEXT_ID"
mkdir -p "$LOGS"

mv "$LOGS_ROOT/slurm_${SLURM_JOB_ID}.tmp.out" "$LOGS/${BASENAME}.out" 2>/dev/null || true
mv "$LOGS_ROOT/slurm_${SLURM_JOB_ID}.tmp.err" "$LOGS/${BASENAME}.err" 2>/dev/null || true

exec >> "$LOGS/${BASENAME}.out" 2>> "$LOGS/${BASENAME}.err"

echo "=================================================="
echo "  Run ID  : $NEXT_ID"
echo "  Job ID  : $SLURM_JOB_ID"
echo "  Node    : $SLURMD_NODENAME"
echo "  Logs dir: $LOGS"
echo "=================================================="

# --- GPU monitor (runs on the host, polls nvidia-smi every 5s) ---
GPU_LOG="$LOGS/${BASENAME}_gpu.csv"
python3 $ANALYSIS/gpu_monitor.py --output "$GPU_LOG" --interval 5 &
GPU_MONITOR_PID=$!
trap "kill $GPU_MONITOR_PID 2>/dev/null; echo 'GPU monitor stopped.'" EXIT
echo "[gpu_monitor] PID=$GPU_MONITOR_PID -> $GPU_LOG"

bash /home/data/projets-aps/projet6/udocker_start_scripts/start_dequant_env.sh --run \
  "export BENCHMARK_DAY=$TODAY BENCHMARK_RUN_ID=$NEXT_ID && cd /Quantum_workspace/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/experiments && python benchmark_bqpgka.py --files bqpgka20_1.txt --qubit-sweep 10 15 20"

kill $GPU_MONITOR_PID 2>/dev/null

# plot_gpu.py needs pandas/matplotlib, not guaranteed on the bare host python3 -
# run it through the venv instead, same as the main script.
bash /home/data/projets-aps/projet6/udocker_start_scripts/start_dequant_env.sh --run \
  "python3 $ANALYSIS/plot_gpu.py --csv $GPU_LOG"

echo ""
echo "Done. Logs dir: $LOGS"
