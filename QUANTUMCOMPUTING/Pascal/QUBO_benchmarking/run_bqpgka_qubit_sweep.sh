#!/bin/bash
# SLURM job: BQPGKA GPU timing sweep (10/15/20 qubits) via benchmark_bqpgka.py
# --qubit-sweep, run inside the DEQUANT udocker container with .venv-pascal.
# Also polls GPU memory/utilization every 5s (analysis/gpu_monitor.py) so
# memory-vs-qubit-count can be inspected afterwards with analysis/plot_gpu.py.
#
# Usage:
#   sbatch run_bqpgka_qubit_sweep.sh
#
# Wrap with the logger from QUBO_benchmarking/:
#   bash run_with_log.sh sbatch run_bqpgka_qubit_sweep.sh
#
# Log naming: %j_bqpgka_qubit_sweep.out/.err (Slurm's own naming, job ID known at
# submit time) is renamed at job start to YYYY-mm-dd_HHhMMmSSs_JOBID_bqpgka_qubit_sweep.out/.err
# once the actual timestamp of job execution is known. GPU CSV/PNG use the same
# timestamp+jobid prefix.

#SBATCH --job-name=bqpgka_qubit_sweep
#SBATCH --output=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs/%j_bqpgka_qubit_sweep.out
#SBATCH --error=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs/%j_bqpgka_qubit_sweep.err
#SBATCH --time=24:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --gres=gpu:1

LOGS=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs
ANALYSIS=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/analysis
TIMESTAMP=$(date '+%Y-%m-%d_%Hh%Mm%Ss')
for ext in out err; do
    OLD=$LOGS/${SLURM_JOB_ID}_bqpgka_qubit_sweep.$ext
    NEW=$LOGS/${TIMESTAMP}_${SLURM_JOB_ID}_bqpgka_qubit_sweep.$ext
    [ -f "$OLD" ] && mv "$OLD" "$NEW"
done
exec >> "$LOGS/${TIMESTAMP}_${SLURM_JOB_ID}_bqpgka_qubit_sweep.out" 2>> "$LOGS/${TIMESTAMP}_${SLURM_JOB_ID}_bqpgka_qubit_sweep.err"

echo "=================================================="
echo "  Job ID  : $SLURM_JOB_ID"
echo "  Node    : $SLURMD_NODENAME"
echo "=================================================="

# --- GPU monitor (runs on the host, polls nvidia-smi every 5s) ---
GPU_LOG=$LOGS/${TIMESTAMP}_${SLURM_JOB_ID}_bqpgka_qubit_sweep_gpu.csv
python3 $ANALYSIS/gpu_monitor.py --output "$GPU_LOG" --interval 5 &
GPU_MONITOR_PID=$!
trap "kill $GPU_MONITOR_PID 2>/dev/null; echo 'GPU monitor stopped.'" EXIT
echo "[gpu_monitor] PID=$GPU_MONITOR_PID -> $GPU_LOG"

bash /home/data/projets-aps/projet6/udocker_start_scripts/start_dequant_env.sh --run \
  "cd /Quantum_workspace/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/experiments && python benchmark_bqpgka.py --files bqpgka20_1.txt --qubit-sweep 10 15 20"

kill $GPU_MONITOR_PID 2>/dev/null

# plot_gpu.py needs pandas/matplotlib, not guaranteed on the bare host python3 -
# run it through the venv instead, same as the main script.
bash /home/data/projets-aps/projet6/udocker_start_scripts/start_dequant_env.sh --run \
  "python3 $ANALYSIS/plot_gpu.py --csv $GPU_LOG"
