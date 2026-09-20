#!/bin/bash
#
# Launch a SLURM array job of one series (from repo root):
#   bash scripts/launch.sh <stage> <group> <series> [ARRAY]
#
#   bash scripts/launch.sh raw_data OBLW  03_reference             # all units
#   bash scripts/launch.sh training test  00_test_online    0-1    # a subset
#   bash scripts/launch.sh rollout  test  00_test_baselines 1      # a single unit
#
# <group> is the scheme for raw_data (schemes/<SCHEME>/) and the experiment for training and
# rollout (experiments/<EXPERIMENT>/). Without ARRAY, every unit of the series file is submitted.





set -euo pipefail

USAGE="Usage: bash scripts/launch.sh <stage> <group> <series> [ARRAY]"
STAGE=${1:?$USAGE}
GROUP=${2:?$USAGE}
SERIES=${3:?$USAGE}

# Stage specific: job name prefix, folder of the groups, ENV variable the runner reads the group from
case "$STAGE" in
    raw_data) PREFIX="raw";   GROUP_DIR="schemes";     GROUP_VAR="SCHEME"     ;;
    training) PREFIX="train"; GROUP_DIR="experiments"; GROUP_VAR="EXPERIMENT" ;;
    rollout)  PREFIX="roll";  GROUP_DIR="experiments"; GROUP_VAR="EXPERIMENT" ;;
    *) echo "Unknown stage: $STAGE (raw_data, training or rollout)" >&2; exit 1 ;;
esac

DEFAULTS_FILE="scripts/$STAGE/defaults.jl"
SERIES_FILE="scripts/$STAGE/$GROUP_DIR/$GROUP/$SERIES.jl"

[[ -f "$SERIES_FILE" ]] || { echo "No such series file: $SERIES_FILE" >&2; exit 1; }

# Array: given explicitly, or every unit of the series file
if [[ $# -ge 4 ]]; then
    ARRAY=$4
else
    N=$(julia --project=. -e '
        using NeuralLongwave, SpeedyWeather, Lux, Dates
        include(ARGS[1])
        include(ARGS[2])
        SERIES_NAME == ARGS[3] || error("SERIES_NAME = $(SERIES_NAME) does not match file name $(ARGS[3])")
        @isdefined(DEFAULTS) || error("$(ARGS[3]) does not define DEFAULTS")
        println(length(SERIES))
    ' "$DEFAULTS_FILE" "$SERIES_FILE" "$SERIES" | tail -n 1)

    [[ "$N" =~ ^[0-9]+$ && "$N" -gt 0 ]] || { echo "Could not count units in $SERIES_FILE" >&2; exit 1; }
    ARRAY="0-$((N-1))"
fi

JOB="${PREFIX}_${GROUP}_${SERIES}"
mkdir -p slurm_logs
echo "Submitting $JOB | array $ARRAY"

sbatch --job-name="$JOB" \
       --array="$ARRAY" \
       --export=ALL,STAGE="$STAGE",$GROUP_VAR="$GROUP",SERIES="$SERIES" \
       --output="slurm_logs/${JOB}_%A_%a.out" \
       --error="slurm_logs/${JOB}_%A_%a.err" \
       scripts/submit.sh
