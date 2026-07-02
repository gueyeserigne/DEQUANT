#!/bin/bash
# SLURM job: QAA-QUBO GPU test (pascal_qaa_to_solve_a_qubo_problem.py), run inside
# the DEQUANT udocker container with .venv-pascal.
#
# Usage:
#   sbatch run_qaa_qubo_test.sh
#
# Log layout: slurm_logs/DD-MM/NNN/NNN_qaa_qubo_test.{out,err}
#   IDs (NNN) are a GLOBAL, monotonically increasing counter across all days —
#   same pattern as run_bqpgka_benchmark.sh / vec2text-mpnet's slurm_train_zero_step_matrix.sh.

#SBATCH --job-name=qaa_qubo_test
#SBATCH --output=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs/slurm_%j.tmp.out
#SBATCH --error=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs/slurm_%j.tmp.err
#SBATCH --time=00:30:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --gres=gpu:1

set -e

# --- Paths (host-side) --------------------------------------------------------
LOGS_ROOT=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs
mkdir -p "$LOGS_ROOT"

# --- Log layout: slurm_logs/DD-MM/NNN/ ---------------------------------------
TODAY=$(date '+%d-%m')
DAY_DIR="$LOGS_ROOT/$TODAY"
mkdir -p "$DAY_DIR"

LAST_ID=$(find "$LOGS_ROOT" -maxdepth 2 -mindepth 2 -type d -name "[0-9][0-9][0-9]" | \
          sed 's|.*/||' | sort -n | tail -1)
NEXT_ID=$(printf "%03d" $(( 10#${LAST_ID:-0} + 1 )))

BASENAME="${NEXT_ID}_qaa_qubo_test"
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

bash /home/data/projets-aps/projet6/udocker_start_scripts/start_dequant_env.sh --run \
  "export BENCHMARK_DAY=$TODAY BENCHMARK_RUN_ID=$NEXT_ID && cd /Quantum_workspace/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/experiments && python pascal_qaa_to_solve_a_qubo_problem.py"

echo ""
echo "Done. Logs dir: $LOGS"
