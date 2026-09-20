### Script for generating rollouts of a target, trained emulator or a baseline
###
### Objective: Roll out a scheme (emulator or target) for both weather and climate against a reference
###
### Run on local machine in REPL (test file):
###     - ENV["EXPERIMENT"] = "test"
###     - ENV["SERIES"] = "00_test_baselines"
###     - ENV["UNIT"] = "0"
###     - include("scripts/rollout/rollout.jl")





### Load packages
using Revise
using NeuralLongwave
using SpeedyWeather
using Lux
using Dates
using Random





### Prepare series file

# Extract slurm variables
slurm_experiment  = get(ENV, "EXPERIMENT", "test")
slurm_series      = get(ENV, "SERIES", "00_test_baselines")
slurm_unit        = parse(Int, get(ENV, "UNIT", "0"))

# Include the default blocks and the series file, and check its name
include(joinpath(@__DIR__, "defaults.jl"))
include(joinpath(@__DIR__, "experiments", slurm_experiment, slurm_series * ".jl"))
@assert SERIES_NAME == slurm_series "Series name mismatch!"

# Choose unit
u = SERIES[slurm_unit+1]





### Build unit configuration

# Merge the unit onto the defaults stacked by the series file (an unknown key is an error)
c = checked_merge(DEFAULTS, u)

# Print the configuration, marking the values this unit set itself
print_unit_config(c, u; title = "$(slurm_experiment) / $(slurm_series) / $(c.unit)")

# A leg runs only if its default block was stacked
do_weather = haskey(c, :weather_raw_unit)
do_climate = haskey(c, :climate_raw_unit)
do_weather || do_climate || error("Neither the weather nor the climate block is stacked - nothing to do!")





### Prepare main code

# Set seed for reproducibility
Random.seed!(c.seed)

# Create output folder
dir = prepare_out_dir(rollout_dir(slurm_experiment, slurm_series, c.unit); overwrite = c.overwrite)


# Spectral grid
spectral_grid = SpectralGrid(truncation = c.truncation, nlayers = c.nlayers)





### Define the to be rolled out scheme

if isnothing(c.baseline)

    # Trained emulator of the SAME experiment/series/unit
    init_dir = emulator_dir(slurm_experiment, slurm_series, c.unit)
    scheme = load(; dir = init_dir, file = "emulator.jld2")
    @info "Rolling out the trained emulator at $(init_dir)!"

else

    # Baseline built from its recipe, every recipe takes the keys it needs from the config and ignores the rest
    scheme = build_scheme(c.baseline, spectral_grid; c...)
    @info "Rolling out the baseline :$(c.baseline)!"
end





### Prepare the two legs

# Weather leg, or nothing if its block was not stacked
weather_config = !do_weather ? nothing : (;
    raw_dir      = raw_data_dir(c.weather_raw_scheme, c.weather_raw_series, c.weather_raw_unit),
    ic_subset    = c.weather_ic_subset,
    probes       = c.weather_probes,
    horizon_days = c.weather_horizon_days,
    n_starts     = c.weather_n_starts,
    field_days   = c.weather_field_days,
)

# Climate leg, or nothing if its block was not stacked
climate_config = !do_climate ? nothing : (;
    raw_dir      = raw_data_dir(c.climate_raw_scheme, c.climate_raw_series, c.climate_raw_unit),
    ic_subset    = c.climate_ic_subset,
    probes       = c.climate_probes,
    horizon_days = c.climate_horizon_days,
    n_windows    = c.climate_n_windows,
)



# Generate both legs of the rollout
rollout_summary = generate_rollout(;
    dir      = dir,
    scheme   = scheme,
    weather  = weather_config,
    climate  = climate_config,
)





### Create and store info.toml file
write_info(;
    dir  = dir,
    file = "info.toml",

    slurm = (;
        experiment = slurm_experiment,
        series     = slurm_series,
        unit       = slurm_unit,
    ),

    provenance = provenance(),

    # Probes are NamedTuples of functions, so store only their names
    config = merge(c,
        (; output_form = string(nameof(typeof(c.output_form)))),
        do_weather ? (; weather_probes = collect(string.(keys(c.weather_probes)))) : (;),
        do_climate ? (; climate_probes = collect(string.(keys(c.climate_probes)))) : (;),
    ),

    scheme = (;
        source = isnothing(c.baseline) ? "trained" : "baseline",
        info_scheme(scheme)...,
    ),

    grid = (;
        grid_type  = string(nameof(spectral_grid.Grid)),
    ),

    weather = !do_weather ? (; skipped = true) : (;
        n_traj       = rollout_summary.weather.n_traj,
        horizon_days = rollout_summary.weather.horizon_days,
    ),

    climate = !do_climate ? (; skipped = true) : (;
        n_traj        = rollout_summary.climate.n_traj,
        horizon_days  = rollout_summary.climate.horizon_days,
        survived_days = collect(rollout_summary.climate.survived_days),
    ),
)
