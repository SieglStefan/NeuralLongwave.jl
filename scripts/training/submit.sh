#!/bin/bash
#SBATCH --partition=standard
#SBATCH --qos=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G
#SBATCH --time=23:00:00

set -euo pipefail

module purge
module load julia/1.10.10
export OPENBLAS_NUM_THREADS=${SLURM_CPUS_PER_TASK:-4}
export JULIA_NUM_THREADS=1

echo "Host $(hostname) | Exp ${NP_EXP:-exp_TEST} | Task ${SLURM_ARRAY_TASK_ID:-0}"
julia --project=. scripts/training/training.jl