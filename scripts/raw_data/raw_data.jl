### Script for generating raw data for training/evaluation
###
### Objective: Propagate a specific target scheme and store its full state on a fixed sampling cadence
###
### Run on local machine in REPL (test file):
###     - ENV["SCHEME"] = "OBLW"
###     - ENV["SERIES"] = "00_test"
###     - ENV["UNIT"] = "0"
###     - include("scripts/raw_data/raw_data.jl")
###
### For loop:
###     for t in 1:12
###         ENV["UNIT"] = string(t)
###         include("scripts/raw_data/raw_data.jl")
###     end





### Load packages
using Revise
using NeuralLongwave
using SpeedyWeather
using Dates
using Random





### Prepare series file

# Extract slurm variables
slurm_scheme      = get(ENV, "SCHEME", "OBLW")
slurm_series      = get(ENV, "SERIES", "00_test")
slurm_unit        = parse(Int, get(ENV, "UNIT", "0"))

# Include the default blocks and the series file, and check its name
include(joinpath(@__DIR__, "defaults.jl"))
include(joinpath(@__DIR__, "schemes", slurm_scheme, slurm_series * ".jl"))
@assert SERIES_NAME == slurm_series "Series name mismatch!"

# Choose unit
u = SERIES[slurm_unit+1]





### Build unit configuration

# Merge the unit onto the defaults stacked by the series file (an unknown key is an error)
c = checked_merge(DEFAULTS, u)

# Print the configuration, marking the values this unit set itself
print_unit_config(c, u; title = "$(slurm_scheme) / $(slurm_series) / $(c.unit)")





### Prepare main code

# Set seed for reproducibility
Random.seed!(c.base_seed)

# Create output folder
dir = prepare_out_dir(raw_data_dir(slurm_scheme, slurm_series, c.unit); overwrite = c.overwrite)


# Spectral grid
spectral_grid = SpectralGrid(truncation = c.truncation, nlayers = c.nlayers)


# Target scheme, every recipe takes the keys it needs from the config and ignores the rest
target = build_scheme(c.target_type, spectral_grid; c...)





### Generate raw data
for ic_nr in 1:c.n_ic

    # Call generating function
    generate_raw_data(
        ic_nr          = ic_nr,
        data_type      = c.data_type,
        dir            = dir,
        seed           = c.base_seed + ic_nr,

        spectral_grid  = spectral_grid,
        model_type     = c.model_type,
        lw_scheme      = target,

        t_spinup       = c.t_spinup,
        start_date     = c.start_date,

        restart_scheme = c.restart_scheme,
        restart_unit   = c.restart_unit,
        restart_ic     = c.restart_ic,
        restart_j      = c.restart_j,

        sample_hours   = c.sample_hours,
        phase_shift    = c.phase_shift,
        sim_days       = c.sim_days,
        offset_hours   = c.offset_hours * (ic_nr - 1),

        fac_pert_T     = c.fac_pert_T,
        fac_pert_q     = c.fac_pert_q,
    )
end





### Create and store info.toml file
write_info(;
    dir  = dir,
    file = "info.toml",

    slurm = (;
        scheme     = slurm_scheme,
        series     = slurm_series,
        unit       = slurm_unit,
    ),

    provenance = provenance(),

    config = c,

    target = (;
        info_scheme(target)...,
    ),

    grid = (;
        grid_type  = string(nameof(spectral_grid.Grid)),
    ),
)
