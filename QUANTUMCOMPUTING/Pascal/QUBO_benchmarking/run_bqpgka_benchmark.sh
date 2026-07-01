#!/bin/bash
# SLURM job: BQPGKA QUBO benchmark via Pulser, run inside the DEQUANT udocker
# container with .venv-pascal.
#
# Usage:
#   sbatch run_bqpgka_benchmark.sh                                 # default: bqpgka20_1.txt
#   sbatch run_bqpgka_benchmark.sh bqpgka20_1.txt bqpgka30_1.txt    # multiple instances
#
# Wrap with the logger from QUBO_benchmarking/:
#   bash run_with_log.sh sbatch ../../../udocker_start_scripts/run_bqpgka_benchmark.sh
#
# Log naming: %j_bqpgka_benchmark.out/.err (Slurm's own naming, job ID known at submit
# time) is renamed at job start to YYYY-mm-dd_HHhMMmSSs_JOBID_bqpgka_benchmark.out/.err
# once the actual timestamp of job execution is known.

#SBATCH --job-name=bqpgka_benchmark
#SBATCH --output=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs/%j_bqpgka_benchmark.out
#SBATCH --error=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs/%j_bqpgka_benchmark.err
#SBATCH --time=02:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --gres=gpu:1

FILES="$*"
if [ -z "$FILES" ]; then
  FILES="bqpgka20_1.txt"
fi

LOGS=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs
TIMESTAMP=$(date '+%Y-%m-%d_%Hh%Mm%Ss')
for ext in out err; do
    OLD=$LOGS/${SLURM_JOB_ID}_bqpgka_benchmark.$ext
    NEW=$LOGS/${TIMESTAMP}_${SLURM_JOB_ID}_bqpgka_benchmark.$ext
    [ -f "$OLD" ] && mv "$OLD" "$NEW"
done
exec >> "$LOGS/${TIMESTAMP}_${SLURM_JOB_ID}_bqpgka_benchmark.out" 2>> "$LOGS/${TIMESTAMP}_${SLURM_JOB_ID}_bqpgka_benchmark.err"

echo "=================================================="
echo "  Job ID  : $SLURM_JOB_ID"
echo "  Node    : $SLURMD_NODENAME"
echo "  Files   : $FILES"
echo "=================================================="

bash /home/data/projets-aps/projet6/udocker_start_scripts/start_dequant_env.sh --run \
  "cd /Quantum_workspace/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/experiments && python benchmark_bqpgka.py --files $FILES"
