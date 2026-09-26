### Job Running
###
### Runs one task of one stage of one series (see series_loader.jl for the job coordinates).
###
### Different possible stages:
###     - target:       raw_data, derive, rollout (reference runs of the target scheme)
###     - experiment:   training, rollout, timing
###
### On the HPC (from the repo root):
###     bash scripts/launch.sh <stage> <group> <series> [ARRAY]
###
### On the local machine in the REPL:
###     ENV["STAGE"] = "training"; ENV["GROUP"] = "test"; ENV["SERIES"] = "00_test_offline"; ENV["UNIT"] = "0"
###     include("scripts/run.jl")
###
### Several tasks in a row:
###     for t in 0:2
###         ENV["UNIT"] = string(t)
###         include("scripts/run.jl")
###     end





### Load packages
using Revise
using NeuralLongwave
using SpeedyWeather
using Lux
using Dates
using Random
using LinearAlgebra





### Series and stage functions

# Job coordinates, default blocks, series file and the tasks of the requested stage
include(joinpath(@__DIR__, "series_loader.jl"))

# One function per stage: stage_<name>(config, job) - timing gets ALL configs of the series at once
for stage_file in ("raw_data", "derive", "training", "rollout", "timing")
    include(joinpath(@__DIR__, "stages", stage_file * ".jl"))
end

# Job description handed to every stage function
job = (; stage = job_stage, kind = job_kind, group = job_group, series = job_series, unit = job_unit)





### Run the task

if job_stage === :timing

    # ONE job for all tasks of the series (interleaved, so they share the machine state)
    configs = [checked_merge(STAGE_DEFAULTS, u) for u in TASKS]
    stage_timing(configs, job)

else

    # Choose the task and merge it onto the stage defaults (an unknown key is an error)
    0 <= job_unit < length(TASKS) || error("UNIT = $(job_unit) out of range - $(job_series) has $(length(TASKS)) $(job_stage) tasks")
    u = TASKS[job_unit + 1]
    c = checked_merge(STAGE_DEFAULTS, u)

    # Print the configuration, marking the values this task set itself
    print_unit_config(c, u; title = "$(job_stage): $(job_group) / $(job_series) / $(c.unit)")

    # Run the stage
    job_stage === :raw_data && stage_raw_data(c, job)
    job_stage === :derive   && stage_derive(c, job)
    job_stage === :training && stage_training(c, job)
    job_stage === :rollout  && stage_rollout(c, job)
end
