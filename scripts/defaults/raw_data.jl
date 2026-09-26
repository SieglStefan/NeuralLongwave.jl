### Raw data defaults
###
### Every key a raw data task may set, as blocks. A target series file stacks the blocks it needs:
###
###     DEFAULTS = (; raw_data = merge(raw_base(), raw_oblw()), ...)
###
### Every task is merged onto its defaults with checked_merge(), so a key no stacked block defines is
### an error, it never falls back to a default silently.
###         - 1) Base
###         - 2) Target schemes (OBLW / ABR)










### 1) Base

# Keys shared by every raw data task
raw_base() = (;

    # General
    unit            = "",                       # name of the unit (smallest job within a series)
    data_type       = :general,                 # label stored with the data (:general, :training or :evaluation)
    base_seed       = 0,                        # base seed for the unit (seed of trajectory t = base_seed + t)
    overwrite       = true,                     # whether an existing output folder is overwritten


    # Trajectories: one per start state, stored as traj_01.jld2, traj_02.jld2, ...
    #   - (run, season): a restart state (see scripts/defaults/restarts.jl)
    #   - :default:      the SpeedyWeather default initial state (only for the spinup itself)
    starts          = [],                       # start state of every trajectory
    only_traj       = nothing,                  # nothing = all trajectories in this task, a number = only this one (one job per trajectory, in parallel)

    # Spectral grid
    truncation      = 32,                       # truncation of the spectral grid
    nlayers         = 8,                        # number of vertical layers


    # SW model
    model_type      = PrimitiveWetModel,        # used SW model


    # Spinup and start date
    t_spinup        = Day(0),                   # spinup time
    start_date      = DateTime(2000, 1, 1),     # sampling starting date (start = :default only)


    # Sampling
    sim_days        = 365,                      # number of sampled days
    sample_hours    = 24f0,                     # nominal sampling cadence in hours (24 = one state per day)
    phase_shift     = 0,                        # shift of steps from the nominal cadence
    offset_hours    = 0f0,                      # offset in hours between the trajectories


    # Perturbation
    fac_pert_T      = 2f0,                      # additive perturbation factor for temperature
    fac_pert_q      = 0.2f0,                    # multiplicative perturbation factor for humidity
)










### 2) Target scheme (OBLW / ABR)

# OneBandLongwave target scheme
raw_oblw() = (;

    # Target scheme
    target_type     = :OBLW,                    # recipe of the scheme the raw data is generated with
    em_ocean        = 0.98f0,                   # ocean emissivity
    em_land         = 0.98f0,                   # land emissivity


    # Restart states the trajectories start from
    restart_scheme  = "OBLW",                   # scheme of the restart state data
    restart_unit    = "default",                # unit of the restart state data
)



# AnalyticBandRadiation target scheme (its recipe in utils_scheme.jl is still a stub)
raw_abr() = (;

    # Target scheme
    target_type     = :ABR,                     # recipe of the scheme the raw data is generated with
    em_ocean        = 1f0,                      # ocean emissivity (hardwired to 1 in ABR)
    em_land         = 1f0,                      # land emissivity (hardwired to 1 in ABR)
    co2             = 280f0,                    # CO2 concentration in ppm


    # Restart states the trajectories start from
    restart_scheme  = "ABR",                    # scheme of the restart state data
    restart_unit    = "default",                # unit of the restart state data
)
