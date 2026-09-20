### Script for training a ConstLW or NeuralLW emulator
###
### Objective: Train a longwave emulator online or offline
###
### Run on local machine in REPL (test file):
###     - ENV["EXPERIMENT"] = "test"
###     - ENV["SERIES"] = "00_test_offline"
###     - ENV["UNIT"] = "0"
###     - include("scripts/training/training.jl")





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
slurm_series      = get(ENV, "SERIES", "00_test_offline")
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





### Prepare main code

# Set seed for reproducibility
Random.seed!(c.seed)

# Create output folder
dir = prepare_out_dir(emulator_dir(slurm_experiment, slurm_series, c.unit); overwrite = c.overwrite)


# Spectral grid
spectral_grid = SpectralGrid(truncation = c.truncation, nlayers = c.nlayers)


# Target scheme, every recipe takes the keys it needs from the config and ignores the rest
target = build_scheme(c.target_type, spectral_grid; c...)





### Define the to be trained emulator

if isnothing(c.init_unit)

    # Fresh emulator built from its recipe (:ConstLW or :NeuralLW)
    emulator = build_scheme(c.emulator_type, spectral_grid; c...)

else

    # Continue from a previously trained emulator (offline -> online fine tuning)
    all(!isnothing, (c.init_experiment, c.init_series, c.init_unit)) || error(
        "A warm start needs init_experiment, init_series and init_unit, got " *
        "$((c.init_experiment, c.init_series, c.init_unit))!")

    init_dir = emulator_dir(c.init_experiment, c.init_series, c.init_unit)
    emulator = load(; dir = init_dir, file = "emulator.jld2")

    check_continuation(emulator, c)
    @info "Continuing from $(init_dir)!"
end





### Prepare training run

# Define loss and train configuration
if c.mode == :offline

    loss_config = LossConfigOffline(;
        zscore_scheme   = c.zscore_scheme,
        zscore_unit     = c.zscore_unit,
        loss_weights    = c.loss_weights,
    )

    train_config = TrainConfigOffline(
        unit            = c.unit,
        dir             = dir,
        seed            = c.seed,

        target_scheme   = c.target_scheme,
        target_unit     = c.target_unit,

        target_ics      = c.target_ics,
        n_ic_val        = c.n_ic_val,

        eta0            = c.eta0,
        eta_decay       = c.eta_decay,
        clip_norm       = c.clip_norm,
        weight_decay    = c.weight_decay,
        loss_config     = loss_config,

        n_epochs        = c.n_epochs,
        n_batches       = c.n_batches,
        batchsize       = c.batchsize,
    )

elseif c.mode == :online

    loss_config = LossConfig(
        spectral_grid   = spectral_grid,
        zscore_scheme   = c.zscore_scheme,
        zscore_unit     = c.zscore_unit,
        n_seg_0         = c.n_seg_0,
        dt_sec          = Leapfrog(spectral_grid).Δt,
        loss_weights    = c.loss_weights,
    )

    train_config = TrainConfigOnline(
        unit            = c.unit,
        dir             = dir,
        seed            = c.seed,

        model           = c.model,
        target          = target,

        restart_scheme  = c.restart_scheme,
        restart_unit    = c.restart_unit,
        restart_ics     = c.restart_ics,
        restart_js      = c.restart_js,

        eta0            = c.eta0,
        eta_decay       = c.eta_decay,
        clip_norm       = c.clip_norm,
        weight_decay    = c.weight_decay,
        loss_config     = loss_config,

        t_spinup        = c.t_spinup,

        n_ic            = c.n_ic,
        n_updates       = c.n_updates,
        n_accum         = c.n_accum,
        n_seg_0         = c.n_seg_0,
        n_seg_inc       = c.n_seg_inc,
        n_gap           = c.n_gap,

        fac_pert_T      = c.fac_pert_T,
        fac_pert_q      = c.fac_pert_q,

        do_autodiff     = c.do_autodiff,
    )
else
    error("Unknown mode: $(c.mode)")
end



# Run the training
emulator_trained = run_training(spectral_grid, emulator, train_config)





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

    config = merge(c, (; output_form = string(nameof(typeof(c.output_form))))),

    target = (;
        info_scheme(target)...,
    ),

    emulator = (;
        info_scheme(emulator_trained)...,
    ),

    grid = (;
        grid_type  = string(nameof(spectral_grid.Grid)),
    ),
)
