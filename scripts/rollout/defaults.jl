### Rollout defaults
###
### Defaults for specific problems are merged together later, e.g.:
###
###     DEFAULTS = merge(base_defaults(), oblw_defaults(), weather_defaults(), climate_defaults())
###
### A leg runs only if its block is stacked. Every unit is merged onto DEFAULTS with checked_merge,
### so a key no stacked block defines is an error, it never falls back to a default silently.
###         - 1) Base
###         - 2) Target scheme (OBLW / ABR)
###         - 3) Legs (weather / climate)
###         - 4) Task split (split_tasks: weather and climate as separate tasks, run in parallel)










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


    # Rolled out scheme
    #   - nothing  -> load the trained emulator of the SAME experiment/series/unit
    #   - a Symbol -> build the scheme from its recipe (:OBLW, :ABR, :ZeroLW, :ConstLW)
    baseline        = nothing,                  # baseline recipe, or nothing for the trained emulator
    output_form     = PlanckOutput(),           # output form of the ConstLW baseline (baseline = :ConstLW only)
)










### 2) Target scheme (OBLW / ABR)

# OneBandLongwave target
oblw_defaults() = (;

    # Radiation constants (baselines only)
    em_ocean             = 0.98f0,              # ocean emissivity
    em_land              = 0.98f0,              # land emissivity
    co2                  = 280f0,               # CO2 concentration in ppm


    # Zscore statistics (baseline = :ConstLW only)
    zscore_scheme        = "OBLW",              # scheme of the used zscore statistics
    zscore_unit          = "default",           # unit of the used zscore statistics


    # Reference raw data and restart states
    weather_raw_scheme   = "OBLW",              # scheme of the weather reference raw data
    climate_restart_scheme = "OBLW",            # scheme of the climate restart states
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


    # Reference raw data and restart states
    weather_raw_scheme   = "ABR",               # scheme of the weather reference raw data
    climate_restart_scheme = "ABR",             # scheme of the climate restart states
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



# Long rollouts from restart states, reduced to drift curves (global means) and yearly mean maps
climate_defaults() = (;

    # Restart states (restart ICs 1-2 are used for training, 3-5 are free for evaluation)
    climate_model_type     = PrimitiveWetModel,     # SW model
    climate_restart_unit   = "default",             # unit of the restart states
    climate_restarts       = [(ic, j) for ic in (4, 5) for j in (1, 3, 5, 7, 9, 11)],  # (restart IC, state): one trajectory each


    # Leg settings
    climate_probes         = CLIMATE_PROBES,    # fields the rollout is judged on
    climate_n_years        = 3,                 # rollout length in years (one mean map per year, year 1 = adjustment)
    climate_year_days      = 366,               # length of one averaging "year" in days (shorter only for tests)
    climate_sample_hours   = 24f0,              # nominal sampling cadence in hours
    climate_phase_shift    = -1,                # precessing through the diurnal cycle (true 24 h means)
    climate_fac_pert_T     = 0f0,               # start state perturbation (0_OBLW_pert: 0.02)
)










### 4) Task split

# Split every unit into two parallel tasks: the weather leg and the climate leg. Both write into the
# same rollout folder (weather.jld2, climate.jld2).
#   - e.g. SERIES = split_tasks(DEFAULTS, [(; unit = "0_OBLW", baseline = :OBLW), ...])
function split_tasks(defaults, units)

    tasks = NamedTuple[]
    for u in units

        # Legs of this unit (a leg runs only if its block was stacked and not switched off)
        c = merge(defaults, u)
        has_weather = haskey(c, :weather_raw_unit) && c.weather_n_starts > 0
        has_climate = haskey(c, :climate_n_years)  && c.climate_n_years  > 0

        # Weather leg: one task, climate switched off
        if has_weather
            push!(tasks, has_climate ? merge(u, (; climate_n_years = 0)) : u)
        end

        # Climate leg: one task, weather switched off
        if has_climate
            push!(tasks, has_weather ? merge(u, (; weather_n_starts = 0)) : u)
        end
    end

    return tasks
end
