### Script for timing all units of a series (trained emulators and baselines) on one machine
###
### Objective: Runtime of every scheme relative to the reference (the FIRST unit, normally 0_OBLW)
###
### Run on local machine in REPL (test file):
###     - ENV["EXPERIMENT"] = "test"
###     - ENV["SERIES"] = "00_test_timing"
###     - include("scripts/timing/timing.jl")
###
### On the HPC: bash scripts/launch.sh timing <experiment> <series>   (one job for all units)





### Load packages
using Revise
using NeuralLongwave
using SpeedyWeather
using Lux
using Dates
using Random
using LinearAlgebra





### Prepare series file

# Extract slurm variables
slurm_experiment  = get(ENV, "EXPERIMENT", "test")
slurm_series      = get(ENV, "SERIES", "00_test_timing")

# Include the default blocks and the series file, and check its name
include(joinpath(@__DIR__, "defaults.jl"))
include(joinpath(@__DIR__, "experiments", slurm_experiment, slurm_series * ".jl"))
@assert SERIES_NAME == slurm_series "Series name mismatch!"

# Merge every unit onto the defaults (an unknown key is an error)
configs = [checked_merge(DEFAULTS, u) for u in SERIES]
c = first(configs)                                      # series-wide settings are taken from the first unit





### Prepare main code

# Set seed for reproducibility
Random.seed!(c.seed)

# Pin BLAS to one thread (the per-column matvecs are tiny, multithreaded BLAS on them is pure noise)
LinearAlgebra.BLAS.set_num_threads(1)
Threads.nthreads() == 1 || @warn "Julia runs with $(Threads.nthreads()) threads - times are not comparable to 1-thread runs!"

# Output folder of the series
dir = mkpath(timing_dir(slurm_experiment, slurm_series))
isfile(joinpath(dir, "timing.jld2")) && !c.overwrite && error("timing.jld2 already exists in $(dir) - set overwrite = true")

# Spectral grid
spectral_grid = SpectralGrid(truncation = c.truncation, nlayers = c.nlayers)





### Define the timed schemes (unit name => scheme), the first one is the reference

# Scheme of one unit
function timed_scheme(cu)

    # Trained emulator of the SAME experiment/series/unit
    isnothing(cu.baseline) &&
        return NeuralLongwave.load(; dir = emulator_dir(slurm_experiment, slurm_series, cu.unit), file = "emulator.jld2")

    # Baseline built from its recipe
    return build_scheme(cu.baseline, spectral_grid; cu...)
end

schemes = (; (Symbol(cu.unit) => timed_scheme(cu) for cu in configs)...)

@info "Timing $(length(schemes)) units, reference :$(first(keys(schemes)))"





### Time all schemes
timing = generate_timing(;
    dir            = dir,
    schemes        = schemes,
    spectral_grid  = spectral_grid,
    model_type     = c.model_type,
    restart_scheme = c.restart_scheme,
    restart_unit   = c.restart_unit,
    restart        = c.restart,
    n_warmup       = c.n_warmup,
    n_sweep_rounds = c.n_sweep_rounds,
    n_step_rounds  = c.n_step_rounds,
)

# Quick look into the log
print_timing(timing)





### Create and store the info file
write_info(;
    dir = dir,

    slurm = (;
        experiment = slurm_experiment,
        series     = slurm_series,
    ),

    provenance = provenance(),

    config = merge(c, (; output_form = string(nameof(typeof(c.output_form))))),

    units = [string(cu.unit) for cu in configs],

    machine = timing.machine,
)
