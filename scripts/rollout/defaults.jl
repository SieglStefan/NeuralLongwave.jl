### Rollout defaults
###
### Every key a rollout unit may set, as blocks. A series file stacks the blocks it needs:
###
###     DEFAULTS = merge(base_defaults(), oblw_defaults(), weather_defaults(), climate_defaults())
###
### A leg runs only if its block is stacked. Every unit is merged onto DEFAULTS with checked_merge,
### so a key no stacked block defines is an error, it never falls back to a default silently.
###         - 1) Base
###         - 2) Target scheme (OBLW / ABR)
###         - 3) Legs (weather / climate)










### 1) Base

# Keys shared by every rollout unit
base_defaults() = (;

    # General
    unit            = "",                       # name of the unit (must match the trained unit of the same series)
    seed            = 7000,                     # used seed for rng
    overwrite       = true,                     # whether an existing output folder is overwritten


    # Spectral grid
    truncation      = 32,                       # truncation of the spectral grid
    nlayers         = 8,                        # number of vertical layers


    # Rolled out emulator
    #   - nothing  -> load the trained emulator of the SAME experiment/series/unit
    #   - a Symbol -> build a baseline from its recipe (:OBLW, :ABR, :ZeroLW, :ConstLW)
    baseline        = nothing,                  # baseline recipe, or nothing for the trained emulator
    output_form     = PlanckOutput(),           # output form of the ConstLW baseline (baseline = :ConstLW only)
)










### 2) Target scheme (OBLW / ABR)
###
### Every key that depends on the target scheme lives here, so switching the target is switching
### ONE block. The reference scheme of a leg is only read if that leg is stacked.

# OneBandLongwave target
oblw_defaults() = (;

    # Radiation constants (baselines only)
    em_ocean             = 0.98f0,              # ocean emissivity
    em_land              = 0.98f0,              # land emissivity
    co2                  = 280f0,               # CO2 concentration in ppm


    # Zscore statistics (baseline = :ConstLW only)
    zscore_scheme        = "OBLW",              # scheme of the used zscore statistics
    zscore_unit          = "default",           # unit of the used zscore statistics


    # Reference raw data
    weather_raw_scheme   = "OBLW",              # scheme of the weather reference raw data
    climate_raw_scheme   = "OBLW",              # scheme of the climate reference raw data
)



# AnalyticBandRadiation target (its recipe in utils_scheme.jl is still a stub)
abr_defaults() = (;

    # Radiation constants (baselines only)
    em_ocean             = 1f0,                 # ocean emissivity (hardwired to 1 in ABR)
    em_land              = 1f0,                 # land emissivity (hardwired to 1 in ABR)
    co2                  = 280f0,               # CO2 concentration in ppm


    # Zscore statistics (baseline = :ConstLW only)
    zscore_scheme        = "ABR",               # scheme of the used zscore statistics
    zscore_unit          = "default",           # unit of the used zscore statistics


    # Reference raw data
    weather_raw_scheme   = "ABR",               # scheme of the weather reference raw data
    climate_raw_scheme   = "ABR",               # scheme of the climate reference raw data
)










### 3) Legs (weather / climate)

# Short rollouts, scored POINTWISE against the reference at matched lead times
weather_defaults() = (;

    # Reference raw dataset (must be sampled without precession, so lead times match exactly)
    weather_raw_series   = "03_reference",      # series of the reference raw data
    weather_raw_unit     = "weather",           # unit of the reference raw data


    # Leg settings
    weather_ic_subset    = 1:2,                 # reference ICs to start from
    weather_probes       = WEATHER_PROBES,      # fields the rollout is judged on
    weather_horizon_days = 14,                  # forecast length in days
    weather_n_starts     = 26,                  # number of start states PER IC
    weather_field_days   = [1, 3, 7, 14],       # lead days for which entire fields are stored
)



# Long rollouts, reduced to drift curves (global means) and bias maps (time means per window)
climate_defaults() = (;

    # Reference raw dataset (must be sampled WITH precession, so the time means are true 24 h means)
    climate_raw_series   = "03_reference",      # series of the reference raw data
    climate_raw_unit     = "climate",           # unit of the reference raw data


    # Leg settings
    climate_ic_subset    = 1:4,                 # reference ICs to start from - one trajectory each
    climate_probes       = CLIMATE_PROBES,      # fields the rollout is judged on
    climate_horizon_days = 3*366,               # rollout length in days (366 d = 54 samples = one window)
    climate_n_windows    = 3,                   # number of averaging windows (3 = one per year)
)
