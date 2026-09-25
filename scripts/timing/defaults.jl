### Timing defaults
###
### Defaults for specific problems are merged together later, e.g.:
###
###     DEFAULTS = merge(base_defaults(), oblw_defaults())
###
### Unlike rollout, ONE job times ALL units of a series (interleaved, so they share the machine state).
### Every unit is merged onto DEFAULTS with checked_merge, so a key no stacked block defines is an error.
###         - 1) Base
###         - 2) Target scheme (OBLW / ABR)










### 1) Base

# Keys shared by every timing unit
base_defaults() = (;

    # General
    unit            = "",                       # name of the unit (must match the trained unit of the same series)
    seed            = 7100,                     # used seed for rng
    overwrite       = true,                     # whether an existing timing.jld2 is overwritten


    # Spectral grid and model
    truncation      = 32,                       # truncation of the spectral grid
    nlayers         = 8,                        # number of vertical layers
    model_type      = PrimitiveWetModel,        # SW model


    # Timed scheme (as in rollout)
    #   - nothing  -> load the trained emulator of the SAME experiment/series/unit
    #   - a Symbol -> build the scheme from its recipe (:OBLW, :ABR, :ZeroLW, :ConstLW)
    baseline        = nothing,                  # baseline recipe, or nothing for the trained emulator
    output_form     = PlanckOutput(),           # output form of the ConstLW baseline (baseline = :ConstLW only)


    # Start state (every scheme starts from the same one)
    restart_unit    = "default",                # unit of the restart states
    restart         = (4, 1),                   # (restart IC, state)


    # Timing (series-wide: only the values of the FIRST unit are used)
    n_warmup        = 10,                       # untimed sweeps + steps per scheme before timing
    n_sweep_rounds  = 1000,                     # timed sweeps per scheme
    n_step_rounds   = 200,                      # timed full timesteps per scheme
)










### 2) Target scheme (OBLW / ABR)

# OneBandLongwave target
oblw_defaults() = (;

    # Radiation constants (baselines only)
    em_ocean        = 0.98f0,                   # ocean emissivity
    em_land         = 0.98f0,                   # land emissivity
    co2             = 280f0,                    # CO2 concentration in ppm


    # Zscore statistics (baseline = :ConstLW only)
    zscore_scheme   = "OBLW",                   # scheme of the used zscore statistics
    zscore_unit     = "default",                # unit of the used zscore statistics


    # Restart states
    restart_scheme  = "OBLW",                   # scheme of the restart states
)
