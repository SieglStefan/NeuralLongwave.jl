### Training defaults
###
### Every key a training task may set, as blocks. An experiment series file stacks the blocks it needs:
###
###     DEFAULTS = (; training = merge(train_base(), train_oblw(), train_offline(), train_neurallw()), ...)
###
### Every task is merged onto its defaults with checked_merge, so a key no stacked block defines is
### an error, it never falls back to a default silently.
###         - 1) Base
###         - 2) Target scheme (OBLW / ABR)
###         - 3) Training mode (offline / online)
###         - 4) Emulator (ConstLW / NeuralLW)










### 1) Base

# Keys shared by every training unit
train_base() = (;

    # General
    unit            = "",                       # name of the unit (subfolder of the series)
    seed            = 5000,                     # used seed for rng
    overwrite       = true,                     # whether an existing output folder is overwritten


    # Spectral grid
    truncation      = 32,                       # truncation of the spectral grid
    nlayers         = 8,                        # number of vertical layers


    # Warm start (nothing = build a fresh emulator)
    init_experiment = nothing,                  # experiment of the emulator to continue from
    init_series     = nothing,                  # series of the emulator to continue from
    init_unit       = nothing,                  # unit of the emulator to continue from


    # Learning parameters
    eta0            = 1f-3,                     # initial learning rate
    eta_decay       = 0.9f0,                    # learning rate decay factor
    clip_norm       = 1f0,                      # gradient clipping norm
    weight_decay    = 0f0,                      # weight decay factor
)










### 2) Target scheme (OBLW / ABR)

# OneBandLongwave target
train_oblw() = (;

    # Target scheme (online: trained against it, offline: only stored in info.toml)
    target_type     = :OBLW,                    # recipe of the target scheme


    # Radiation constants (of the target and the emulator)
    em_ocean        = 0.98f0,                   # ocean emissivity
    em_land         = 0.98f0,                   # land emissivity
    co2             = 280f0,                    # CO2 concentration in ppm


    # Data of the target scheme
    zscore_scheme   = "OBLW",                   # scheme of the used zscore statistics
    zscore_unit     = "default",                # unit of the used zscore statistics
    target_scheme   = "OBLW",                   # scheme of the target dataset (offline only)
    restart_scheme  = "OBLW",                   # scheme of the restart state data (online only)


    # Emulator inputs (NeuralLW only), provably complete for OBLW
    inputs          = [:T, :sinlat2, :ps, :Usfc],    # input names of the network (see INPUTS in input.jl)
)



# AnalyticBandRadiation target
train_abr() = (;

    # Target scheme (online: trained against it, offline: only stored in info.toml)
    target_type     = :ABR,                     # recipe of the target scheme


    # Radiation constants (of the target and the emulator)
    em_ocean        = 1f0,                      # ocean emissivity (hardwired to 1 in ABR)
    em_land         = 1f0,                      # land emissivity (hardwired to 1 in ABR)
    co2             = 280f0,                    # CO2 concentration in ppm


    # Data of the target scheme
    zscore_scheme   = "ABR",                    # scheme of the used zscore statistics
    zscore_unit     = "default",                # unit of the used zscore statistics
    target_scheme   = "ABR",                    # scheme of the target dataset (offline only)
    restart_scheme  = "ABR",                    # scheme of the restart state data (online only)


    # Emulator inputs (NeuralLW only), humidity is needed for the band absorption
    inputs          = [:T, :log10q, :ps, :sst, :lst, :lf],   # input names of the network (see INPUTS in input.jl)
)










### 3) Training mode (offline / online)

# Training against a pre-generated column_io dataset
train_offline() = (;

    # Mode
    mode            = :offline,                 # training mode


    # Loss
    loss_weights    = (; olw = 1f0, slwd = 1f0, dT = 1f0),      # weights of the loss terms


    # Target dataset (a column_io dataset: data/column_io/<target_scheme>/<target_unit>/)
    target_unit     = "training_data",          # unit of the target dataset
    target_trajs    = 1:4,                      # raw data trajectories of the target dataset used here
    n_val_trajs     = 1,                        # nr. of trajectories held out for validation (the last ones)


    # Training loop
    n_epochs        = 50,                       # number of epochs
    n_batches       = 100,                      # number of batches per epoch
    batchsize       = 1024,                     # training batch size (samples per update)
)



# Training by differentiating through the SW timestepping
train_online() = (;

    # Mode
    mode            = :online,                  # training mode


    # Loss
    loss_weights    = (; T = 1f0, olw = 1f0, slwd = 1f0),       # weights of the loss terms


    # SW model
    model           = PrimitiveWetModel,        # used SW model
    t_spinup        = Day(30),                  # spinup time before training


    # Restart states (data/restart_states/<restart_scheme>/<restart_unit>/)
    restart_unit    = "default",                # unit of the restart state data
    restarts        = TRAIN_RESTARTS,           # (run, season) restart states the start states are drawn from


    # Training loop
    n_starts        = 5,                        # nr. of start states, spread evenly over restarts
    n_updates       = 25,                       # nr. of emulator updates per start state
    n_accum         = 4,                        # nr. of trajectory gradients accumulated per update
    n_seg_0         = 10,                       # nr. of steps of the initial differentiation segment
    n_seg_inc       = 0,                        # increase of the differentiation segment per start state
    n_gap           = 50,                       # nr. of timesteps between differentiation segments


    # Perturbation
    fac_pert_T      = 2f0,                      # additive perturbation factor for temperature
    fac_pert_q      = 0.2f0,                    # multiplicative perturbation factor for humidity


    # Autodiff
    do_autodiff     = true,                     # whether Enzyme.autodiff is used
)










### 4) Emulator (ConstLW / NeuralLW)

# Global constant parameters, no network (so none of the architecture keys exist here)
train_constlw() = (;
    emulator_type   = :ConstLW,                 # recipe of the trained emulator
    output_form     = PlanckOutput(),           # output form of the emulator
)



# Neural network emulator (its inputs come from the target block)
train_neurallw() = (;

    # Emulator
    emulator_type   = :NeuralLW,                # recipe of the trained emulator
    output_form     = PlanckOutput(),           # output form of the emulator


    # Architecture
    arch_type       = :MLP,                     # architecture type (MLP or RNN)
    n_hidden        = 2,                        # number of hidden layers (MLP only)
    width           = 32,                       # width of the hidden layers
    act             = tanh,                     # activation function
)
