#!/bin/bash
#
# Launch a SLURM array job of one stage of one series (from the repo root):
#   bash scripts/launch.sh <stage> <group> <series> [ARRAY]
#
#   <stage>     raw_data, derive, training, rollout or timing
#   <group>     a target scheme  (scripts/targets/<group>/, e.g. OBLW)
#               or an experiment (scripts/experiments/<group>/, e.g. exp_B)
#   <series>    file name of the series, without .jl
#   [ARRAY]     optional: which tasks of the stage, e.g. 2 or 0-3 (numbered from 0 in the series file)
#               without it, every task of the stage is submitted (timing: always ONE job for all tasks)
#
# Examples:
#   bash scripts/launch.sh raw_data OBLW  01_setup 0                # a single task
#   bash scripts/launch.sh derive   OBLW  01_setup 1-3              # a subset
#   bash scripts/launch.sh training exp_B 01_NLW_MLP_offline        # all tasks
#   bash scripts/launch.sh rollout  exp_B 01_NLW_MLP_offline
#   bash scripts/launch.sh timing   exp_B 01_NLW_MLP_offline        # one exclusive job, all tasks





set -euo pipefail

USAGE="Usage: bash scripts/launch.sh <stage> <group> <series> [ARRAY]"
STAGE=${1:?$USAGE}
GROUP=${2:?$USAGE}
SERIES=${3:?$USAGE}

# Stage specific job name prefix
case "$STAGE" in
    raw_data) PREFIX="raw"    ;;
    derive)   PREFIX="derive" ;;
    training) PREFIX="train"  ;;
    rollout)  PREFIX="roll"   ;;
    timing)   PREFIX="time"   ;;
    *) echo "Unknown stage: $STAGE (raw_data, derive, training, rollout or timing)" >&2; exit 1 ;;
esac

# The series file must exist as a target or an experiment series
[[ -f "scripts/targets/$GROUP/$SERIES.jl" || -f "scripts/experiments/$GROUP/$SERIES.jl" ]] ||
    { echo "No series file $GROUP/$SERIES.jl in scripts/targets/ or scripts/experiments/" >&2; exit 1; }

# Array: given explicitly, or every task of the stage (timing: ONE job times all tasks)
if [[ "$STAGE" == "timing" ]]; then
    ARRAY=0
elif [[ $# -ge 4 ]]; then
    ARRAY=$4
else
    N=$(STAGE="$STAGE" GROUP="$GROUP" SERIES="$SERIES" julia --project=. -e '
        using NeuralLongwave, SpeedyWeather, Lux, Dates
        include("scripts/series_loader.jl")
        println(length(TASKS))
    ' | tail -n 1)

    [[ "$N" =~ ^[0-9]+$ && "$N" -gt 0 ]] || { echo "Could not count the $STAGE tasks of $GROUP/$SERIES" >&2; exit 1; }
    ARRAY="0-$((N-1))"
fi

JOB="${PREFIX}_${GROUP}_${SERIES}"
mkdir -p slurm_logs
echo "Submitting $JOB | array $ARRAY"

sbatch --job-name="$JOB" \
       --array="$ARRAY" \
       --export=ALL,STAGE="$STAGE",GROUP="$GROUP",SERIES="$SERIES" \
       --output="slurm_logs/${JOB}_%A_%a.out" \
       --error="slurm_logs/${JOB}_%A_%a.err" \
       scripts/submit.sh
