### Series Loader
###
### Reads the job coordinates from ENV, includes every default block and the series file, and picks
### the tasks of the requested stage. Included by run.jl, and by launch.sh to count the tasks.
###
### Job coordinates (ENV):
###     - STAGE:    raw_data, derive, training, rollout, timing
###     - GROUP:    a target scheme  -> scripts/targets/<GROUP>/<SERIES>.jl      (e.g. OBLW)
###                 an experiment    -> scripts/experiments/<GROUP>/<SERIES>.jl  (e.g. exp_B)
###     - SERIES:   file name of the series, without .jl (e.g. 01_CLW_offline)
###     - UNIT:     index of the task within the stage, starting at 0 (the SLURM array index)
###
### A series file defines:
###     - SERIES_NAME   its own file name (checked)
###     - DEFAULTS      (; stage = stacked default blocks, ...) for every stage it supports
###     - SERIES        (; stage = [task, task, ...], ...), the same stages as DEFAULTS
###
### Which stage belongs to which kind of series:
###     - target:       raw_data, derive, rollout (reference runs of the target scheme)
###     - experiment:   training, rollout, timing





### Define and setup job

# Job coordinates
job_stage  = Symbol(get(ENV, "STAGE", "training"))
job_group  = get(ENV, "GROUP", "test")
job_series = get(ENV, "SERIES", "00_test_offline")
job_unit   = parse(Int, get(ENV, "UNIT", "0"))


# Restart states of training and evaluation (TRAIN_RESTARTS, EVAL_RESTARTS), used by the default blocks
include(joinpath(@__DIR__, "defaults", "restarts.jl"))

# Include all default blocks of every stage (series files need it)
include(joinpath(@__DIR__, "defaults", "raw_data.jl"))
include(joinpath(@__DIR__, "defaults", "derive.jl"))
include(joinpath(@__DIR__, "defaults", "training.jl"))
include(joinpath(@__DIR__, "defaults", "rollout.jl"))
include(joinpath(@__DIR__, "defaults", "timing.jl"))

# Helpers for building the task lists of a series file
names_only(units) = [(; unit = u.unit) for u in units]      # trained units reduced to their names (rollout, timing)
weather_only(u)   = merge(u, (; climate_n_years = 0))       # a rollout task without its climate leg





### Prepare SERIES file

# Series file: either a target or an experiment series
target_file     = joinpath(@__DIR__, "targets",     job_group, job_series * ".jl")
experiment_file = joinpath(@__DIR__, "experiments", job_group, job_series * ".jl")

isfile(target_file) && isfile(experiment_file) &&
    error("$(job_group)/$(job_series) exists as a target AND as an experiment series - rename one!")

job_kind = isfile(target_file)     ? :target     :
           isfile(experiment_file) ? :experiment :
           error("No series file $(job_group)/$(job_series).jl in scripts/targets/ or scripts/experiments/")

Base.include(@__MODULE__, job_kind === :target ? target_file : experiment_file)





### Check SERIES file

# Check the series file
SERIES_NAME == job_series || error("SERIES_NAME = $(SERIES_NAME) does not match the file name $(job_series)")
keys(DEFAULTS) == keys(SERIES) || error("DEFAULTS and SERIES of $(job_series) define different stages: " *
                                         "$(keys(DEFAULTS)) vs. $(keys(SERIES))")
haskey(SERIES, job_stage) || error("$(job_group)/$(job_series) has no $(job_stage) stage - it has $(keys(SERIES))")

# Stage the series supports for its kind
allowed = job_kind === :target ? (:raw_data, :derive, :rollout) : (:training, :rollout, :timing)
job_stage in allowed || error("A $(job_kind) series can not run the $(job_stage) stage (allowed: $(allowed))")


# Defaults and tasks of the requested stage
STAGE_DEFAULTS = DEFAULTS[job_stage]        # e.g. training = (train_base, train_oblw,...)
TASKS          = SERIES[job_stage]          # e.g. timing = (OBLW, ZeroLW, direct_offline,...)