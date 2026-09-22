### Raw data defaults
###
### Every key a raw data unit may set, as blocks. A series file stacks the blocks it needs:
###
###     DEFAULTS = merge(base_defaults(), oblw_defaults())
###
### Every unit is merged onto DEFAULTS with checked_merge(), so a key no stacked block defines is
### an error, it never falls back to a default silently.
###         - 1) Base
###         - 2) Target schemes (OBLW / ABR)










### 1) Base

# Keys shared by every raw data unit
base_defaults() = (;

    # General
    unit            = "",                       # name of the unit (smallest job within a series)
    n_ic            = 1,                        # number of initial conditions
    data_type       = :general,                 # label stored with the data (:general, :training or :evaluation)
    base_seed       = 0,                        # base seed for the unit (seed = base_seed + ic)
    overwrite       = true,                     # whether an existing output folder is overwritten


    # Spectral grid
    truncation      = 32,                       # truncation of the spectral grid
    nlayers         = 8,                        # number of vertical layers


    # SW model
    model_type      = PrimitiveWetModel,        # used SW model


    # Spinup and start date
    t_spinup        = Day(0),                   # spinup time
    start_date      = DateTime(2000, 1, 1),     # sampling starting date (only used without a restart)


    # Sampling
    sim_days        = 365,                      # number of sampled days
    sample_hours    = 24f0,                     # nominal sampling cadence in hours (24 = one state per day)
    phase_shift     = 0,                        # shift of steps from the nominal cadence
    offset_hours    = 0f0,                      # offset in hours between the ICs


    # Perturbation
    fac_pert_T      = 2f0,                      # additive perturbation factor for temperature
    fac_pert_q      = 0.2f0,                    # multiplicative perturbation factor for humidity
)










### 2) Target scheme (OBLW / ABR)

# OneBandLongwave target scheme
oblw_defaults() = (;

    # Target scheme
    target_type     = :OBLW,                    # recipe of the scheme the raw data is generated with
    em_ocean        = 0.98f0,                   # ocean emissivity
    em_land         = 0.98f0,                   # land emissivity


    # Restart state
    restart_scheme  = "OBLW",                   # scheme of the restart state data
    restart_unit    = "default",                # unit of the restart state data
    restart_ic      = 1,                        # specific restart IC (or a list, cycled over the ICs)
    restart_j       = 1,                        # specific restart season (or a list, cycled over the ICs)
)



# AnalyticBandRadiation target scheme (its recipe in utils_scheme.jl is still a stub)
abr_defaults() = (;

    # Target scheme
    target_type     = :ABR,                     # recipe of the scheme the raw data is generated with
    em_ocean        = 1f0,                      # ocean emissivity (hardwired to 1 in ABR)
    em_land         = 1f0,                      # land emissivity (hardwired to 1 in ABR)
    co2             = 280f0,                    # CO2 concentration in ppm


    # Restart state
    restart_scheme  = "ABR",                    # scheme of the restart state data
    restart_unit    = "default",                # unit of the restart state data
    restart_ic      = 1,                        # specific restart IC (or a list, cycled over the ICs)
    restart_j       = 1,                        # specific restart season (or a list, cycled over the ICs)
)