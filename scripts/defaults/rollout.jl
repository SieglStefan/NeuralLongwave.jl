### Rollout defaults
###
### Every key a rollout task may set, as blocks. A series file stacks the blocks it needs:
###
###     DEFAULTS = (; rollout = merge(roll_base(), roll_oblw(), roll_weather(), roll_climate()), ...)
###
### A leg runs only if its block is stacked. Every task is merged onto its defaults with checked_merge,
### so a key no stacked block defines is an error, it never falls back to a default silently.
###         - 1) Base
###         - 2) Target scheme (OBLW / ABR)
###         - 3) Legs (weather / climate)
###         - 4) Task split (split_tasks: weather and climate as separate tasks, run in parallel)
###
### Where a task writes to:
###     - experiment series:    results/<experiment>/<series>/<unit>/rollout/
###     - target series:        results/<SCHEME>/<unit>/  (reference runs, e.g. results/OBLW/climate_ref/)










### 1) Base

# Keys shared by every rollout unit
roll_base() = (;

    # General
    unit            = "",                       # name of the unit (must match the trained unit of the same series)
    seed            = 7000,                     # used seed for rng
    overwrite       = true,                     # whether an existing output folder is overwritten


    # Spectral grid
    truncation      = 32,                       # truncation of the spectral grid
    nlayers         = 8,                        # number of vertical layers


    # Rolled out scheme
    #   - nothing  -> load the trained emulator of the SAME experiment/series/unit (experiment series only)
    #   - a Symbol -> build the scheme from its recipe (:OBLW, :ABR, :ZeroLW, :ConstLW)
    baseline        = nothing,                  # baseline recipe, or nothing for the trained emulator
)










### 2) Target scheme (OBLW / ABR)

# OneBandLongwave target
roll_oblw() = (;

    # Radiation constants (baselines only)
    em_ocean             = 0.98f0,              # ocean emissivity
    em_land              = 0.98f0,              # land emissivity
    co2                  = 280f0,               # CO2 concentration in ppm


    # Reference raw data and restart states
    weather_raw_scheme   = "OBLW",              # scheme of the weather reference raw data
    climate_restart_scheme = "OBLW",            # scheme of the climate restart states
)



# AnalyticBandRadiation target (its recipe in utils_scheme.jl is still a stub)
roll_abr() = (;

    # Radiation constants (baselines only)
    em_ocean             = 1f0,                 # ocean emissivity (hardwired to 1 in ABR)
    em_land              = 1f0,                 # land emissivity (hardwired to 1 in ABR)
    co2                  = 280f0,               # CO2 concentration in ppm


    # Reference raw data and restart states
    weather_raw_scheme   = "ABR",               # scheme of the weather reference raw data
    climate_restart_scheme = "ABR",             # scheme of the climate restart states
)










### 3) Legs (weather / climate)

# Short rollouts, scored POINTWISE against the reference at matched lead times
roll_weather() = (;

    # Reference raw dataset (must be sampled without precession, so lead times match exactly)
    weather_raw_series   = "03_reference",      # series of the reference raw data
    weather_raw_unit     = "weather",           # unit of the reference raw data


    # Leg settings
    weather_trajs        = 1:2,                 # reference trajectories to start from
    weather_probes       = WEATHER_PROBES,      # fields the rollout is judged on
    weather_horizon_days = 14,                  # forecast length in days
    weather_n_starts     = 26,                  # number of start states PER reference trajectory
    weather_field_days   = [1, 3, 7, 14],       # lead days for which entire fields are stored
)



# Long rollouts from restart states, reduced to drift curves (global means) and yearly mean maps
roll_climate() = (;

    # Restart states (see scripts/defaults/restarts.jl)
    climate_model_type     = PrimitiveWetModel,     # SW model
    climate_restart_unit   = "default",             # unit of the restart states
    climate_restarts       = EVAL_RESTARTS,         # (run, season) restart states: one trajectory each


    # Leg settings
    climate_probes         = CLIMATE_PROBES,    # fields the rollout is judged on
    climate_n_years        = 3,                 # rollout length in years (one mean map per year, year 1 = adjustment)
    climate_year_days      = 366,               # length of one averaging "year" in days (shorter only for tests)
    climate_sample_hours   = 24f0,              # nominal sampling cadence in hours
    climate_phase_shift    = -1,                # precessing through the diurnal cycle (true 24 h means)
    climate_fac_pert_T     = 0f0,               # start state perturbation (OBLW climate_noise: 0.02)
)










### 4) Task split

# Split every unit into two parallel tasks: the weather leg and the climate leg. Both write into the
# same rollout folder (weather.jld2, climate.jld2).
#   - e.g. rollout = split_tasks(DEFAULTS.rollout, [(; unit = "b_OBLW", baseline = :OBLW), ...])
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
