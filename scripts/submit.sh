#!/bin/bash
#SBATCH --partition=standard
#SBATCH --qos=short
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#
# One array task of one stage of a series, submitted by scripts/launch.sh (which exports STAGE,
# GROUP and SERIES; the array index becomes UNIT).





set -euo pipefail

module purge
module load julia/1.10.10
export OPENBLAS_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}
export JULIA_NUM_THREADS=1

export UNIT="${SLURM_ARRAY_TASK_ID:-0}"

echo "Host $(hostname) | Stage ${STAGE} | Group ${GROUP} | Series ${SERIES} | Unit ${UNIT}"
julia --project=. scripts/run.jl
