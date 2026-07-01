#!/bin/bash
# SLURM job: QAA-QUBO GPU test (pascal_qaa_to_solve_a_qubo_problem.py), run inside
# the DEQUANT udocker container with .venv-pascal.
#
# Usage:
#   sbatch run_qaa_qubo_test.sh
#
# Wrap with the logger from QUBO_benchmarking/:
#   bash run_with_log.sh sbatch run_qaa_qubo_test.sh
#
# Log naming: %j_qaa_qubo_test.out/.err (Slurm's own naming, job ID known at submit
# time) is renamed at job start to YYYY-mm-dd_HHhMMmSSs_JOBID_qaa_qubo_test.out/.err
# once the actual timestamp of job execution is known.

#SBATCH --job-name=qaa_qubo_test
#SBATCH --output=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs/%j_qaa_qubo_test.out
#SBATCH --error=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs/%j_qaa_qubo_test.err
#SBATCH --time=00:30:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --gres=gpu:1

LOGS=/home/data/projets-aps/projet6/Quantum_Internship_May_June_2026/DEQUANT/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/slurm_logs
TIMESTAMP=$(date '+%Y-%m-%d_%Hh%Mm%Ss')
for ext in out err; do
    OLD=$LOGS/${SLURM_JOB_ID}_qaa_qubo_test.$ext
    NEW=$LOGS/${TIMESTAMP}_${SLURM_JOB_ID}_qaa_qubo_test.$ext
    [ -f "$OLD" ] && mv "$OLD" "$NEW"
done
exec >> "$LOGS/${TIMESTAMP}_${SLURM_JOB_ID}_qaa_qubo_test.out" 2>> "$LOGS/${TIMESTAMP}_${SLURM_JOB_ID}_qaa_qubo_test.err"

echo "=================================================="
echo "  Job ID  : $SLURM_JOB_ID"
echo "  Node    : $SLURMD_NODENAME"
echo "=================================================="

bash /home/data/projets-aps/projet6/udocker_start_scripts/start_dequant_env.sh --run \
  "cd /Quantum_workspace/QUANTUMCOMPUTING/Pascal/QUBO_benchmarking/experiments && python pascal_qaa_to_solve_a_qubo_problem.py"
