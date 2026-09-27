### Rollout generation
###
### Generates the computationally expensive rollouts later reduced by evaluation.
###         - 1) Rollout Wrapper
###         - 2) Weather leg
###         - 3) Climate leg
###         - 4) Helpers
###
### One rollout consists of TWO legs, mostly generated together for the same scheme:
###
###     - weather:  14 days:    The run still tracks the reference trajectory, so it is scored
###                 POINTWISE at matched lead times against the stored reference states.
###
###     - climate:  3 years:    The run decorrelates from any reference, so pointwise scores
###                 are meaningless. Started from restart states, only temporal and spatial means are stored
###
### The two legs have different shapes and very different runtimes. Therefore, they are stored separately
### as weather.jld2 and climate.jld2 in the same rollout folder.










### 1) Rollout Wrapper

# Generate both legs of one rollout and store them as weather.jld2 / climate.jld2
function generate_rollout(;
    dir,                # output folder, results/<series>/<experiment>/<variant>/rollout
    scheme,             # scheme to roll out
    weather,            # weather leg settings, or nothing to skip the leg
    climate,            # climate leg settings, or nothing to skip the leg
)

    # Nothing selected for rollout
    isnothing(weather) && isnothing(climate) && error("both legs are nothing - nothing to do!")


    # Weather leg
    w_summary = if isnothing(weather)
        nothing
    else
        w = rollout_weather(scheme; weather...)
        save(w; dir, file = "weather.jld2")
        @info "Weather leg stored at $(dir)!"
        (; n_traj = length(w.traj_raw), horizon_days = last(w.days))
    end

    # Climate leg
    c_summary = if isnothing(climate)
        nothing
    else
        c = rollout_climate(scheme; climate...)
        save(c; dir, file = "climate.jld2")
        @info "Climate leg stored at $(dir)!"
        (; n_traj = length(c.traj_run), horizon_days = last(c.days), survived_days = c.survived_days)
    end


    # Return a small summary for the info.toml of the run
    return (; weather = w_summary, climate = c_summary)
end










### 2) Weather leg (14 day rollouts)

# Short rollouts, scored pointwise against the reference trajectory at matched lead times
function rollout_weather(
    scheme;             # scheme to roll out
    raw_dir,            # reference raw dataset
    trajs,              # reference raw data trajectories to start from
    probes,             # fields the rollout is judged on
    horizon_days,       # forecast length in days
    n_starts,           # number of start states PER reference trajectory
    field_days,         # lead days for which entire fields are stored (e.g. for heatmaps)
)


    # Read reference metadata
    meta = with_raw_data(raw_dir, first(trajs)) do d
        (; d.spectral_grid, d.model_type, d.n_states, d.gap_steps, d.steps_per_day)
    end

    # Extract grid dimensions (number of grid points per state and NT of number of vertical layers per probe)
    npoints = meta.spectral_grid.npoints
    probe_layers = map(e -> e.kind === :profile ? meta.spectral_grid.nlayers : 1, probes)      # e.g. = (; T = 8, olw = 1, ...)



    # Real distance between two samples, in days
    gap_days = meta.gap_steps / meta.steps_per_day

    # Length of horizon_days in reference samples units
    #   - (e.g. horizon_days = 14, gap_days = 8h -> horizon_sampled = 14*3 = 42)
    horizon_sampled = round(Int, horizon_days / gap_days)

    # field_days converted into reference sample units (e.g. [1, 3] -> [3, 9])
    field_sampled = sort!(unique(round.(Int, field_days ./ gap_days)))

    # Evenly spaced starting times across a year in reference sample units
    starts_sampled = round.(Int, range(0, 366 / gap_days, length = n_starts + 1))[1:end-1]

    # Check that the last trajectory still ends inside the reference (states are d[0] ... d[n_states-1])
    last(starts_sampled) + horizon_sampled <= meta.n_states - 1 ||
        error("last start $(last(starts_sampled)) + horizon $(horizon_sampled) exceeds the reference ($(meta.n_states - 1) samples)!")

    # Number of total trajectories
    n_traj = length(trajs) * n_starts



    # Grid area weights, so every score is area weighted
    w = area_weights(meta.spectral_grid)

    # Utility functions for allocating properly shaped arrays
    curve(n_layers) = zeros(Float32, horizon_sampled, n_layers, n_traj)                 # for metric curves, e.g. RMSE
    field(n_layers) = zeros(Float32, length(field_sampled), npoints, n_layers, n_traj)  # for full global fields

    # Scores per probe
    #   - e.g. (; T = (; rmse = (sample nr., layer nr., trajectory nr.), bias = ..., maxdiff = ...), olw = ...)
    scores = map(n_layers -> (; rmse = curve(n_layers), bias = curve(n_layers), maxdiff = curve(n_layers)), probe_layers)



    # Create containers for the fields of the scheme and the reference
    field_run, field_ref = map(field, probe_layers), map(field, probe_layers)

    # Labels of the trajectory axis, encoding every trajectory with (reference trajectory, start sample)
    traj_raw, traj_start = Int[], Int[]



    # Index counter for trajectories
    i_traj = 0

    ### Main loop: roll out every trajectory, scoring each lead sample as it is reached
    # Loop over reference trajectories
    for raw in trajs
        with_raw_data(raw_dir, raw) do d

            # State the reference built its semi-implicit operators from, read once per reference trajectory
            state0 = d[0]


            # Loop over all starts (evenly distributed across a year)
            for s in starts_sampled

                # Count and label this trajectory
                i_traj += 1
                push!(traj_raw, raw)
                push!(traj_start, s)


                # Fresh simulation for every trajectory
                sim = initialize!(meta.model_type(meta.spectral_grid; longwave_radiation = scheme))
                spinup_leapfrog!(sim; total_steps = horizon_sampled * meta.gap_steps)

                # Build the implicit operators from state0 (as the reference did), then overwrite the prognostic state with start sample s
                restart_from!(sim, state0, 0)
                copy!(sim.variables, d[s])


                # Index counter for stored fields
                i_field = 0


                # Loop over lead samples (1:horizon_days in sample units)
                for l in 1:horizon_sampled

                    # Propagate one reference gap and load the reference state at sample s+l
                    sim_timesteps!(sim, meta.gap_steps)
                    ref_state = d[s+l]

                    # Increase counter if this lead sample is a field sample
                    if l in field_sampled
                        i_field += 1
                    end


                    # Loop over to be probed fields
                    for (p, probe) in pairs(probes)

                        # Extract probe from run and reference state
                        run = probe.func(sim.variables)
                        ref = probe.func(ref_state)


                        # Loop over layers (all layers for profiles, one pass for scalars)
                        for k in 1:probe_layers[p]

                            # Extract layer k of run and reference
                            x, y = get_layer(run, k), get_layer(ref, k)

                            # Error of the rollout against the reference state
                            scores[p].rmse[l,k,i_traj]    = wrmse(x, y, w)
                            scores[p].bias[l,k,i_traj]    = wbias(x, y, w)
                            scores[p].maxdiff[l,k,i_traj] = maxdiff(x, y)

                            # Store the full fields on selected lead samples
                            if l in field_sampled
                                field_run[p][i_field,:,k,i_traj] .= x
                                field_ref[p][i_field,:,k,i_traj] .= y
                            end
                        end
                    end
                end

                @info "Weather rollout $(i_traj)/$(n_traj) finished! (reference trajectory $(raw), start sample $(s))"
            end
        end
    end


    # Calculate sample lead times in days 
    #   - (e.g. [1,2,3,4,...] -> [0.33, 0.66, 1.0, 1.33, ...])
    days = Float32.((1:horizon_sampled) .* gap_days)


    # Collect everything (everything per trajectory, nothing averaged)
    return (;
        # Identity
        leg             = :weather,
        raw_dir         = raw_dir,
        spectral_grid   = meta.spectral_grid,
        probes          = keys(probes),

        # Time axis (lead samples)
        gap_days        = Float32(gap_days),          # days between two reference samples
        horizon_days    = Float32(horizon_days),      # requested horizon
        horizon_samples = horizon_sampled,            # horizon actually rolled out
        days            = days,                       # (horizon_samples,) lead time of every sample

        # Trajectory axis
        traj_raw,                                     # (n_traj,) reference trajectory every trajectory started from
        traj_start,                                   # (n_traj,) start sample of every trajectory

        # Scores: (; T = (; rmse, bias, maxdiff), olw = ...), each (horizon_samples, layer, n_traj)
        scores,

        # Full fields on selected lead days
        field_days    = Float32.(field_sampled .* gap_days),   # (n_fields,)
        field_run, field_ref,                                  # each (n_fields, npoints, layer, n_traj)
    )
end










### 3) Climate leg (multi-year rollouts)

# Long rollouts, reduced to global-mean time series and one time-mean map per year
function rollout_climate(
    scheme;                 # scheme to roll out
    spectral_grid,          # spectral grid
    model_type,             # SpeedyW model (e.g. PrimitiveWetModel)
    restart_scheme,         # scheme folder of the restart states
    restart_unit,           # unit folder of the restart states
    restarts,               # (run, season) restart states to start from - one trajectory each
    probes,                 # fields the rollout is judged on
    n_years,                # rollout length in years (one time-mean map per year)
    year_days,              # length of one averaging year in days (366, shorter only for tests)
    sample_hours,           # base time difference between consecutive samples in hours (e.g. 24)
    phase_shift,            # shift of steps from the base difference between samples (precession through diurnal cycle)
    fac_pert_T,             # additive temperature perturbation of the start state (0 = none)
    seed,                   # seed of the perturbation
)

    # Grid dimensions and number of trajectories (one per restart)
    npoints      = spectral_grid.npoints
    probe_layers = map(e -> e.kind === :profile ? spectral_grid.nlayers : 1, probes)      # e.g. = (; T = 8, olw = 1, ...)
    n_traj       = length(restarts)

    

    # Extract timestepping and convert between steps and days/hours
    Δt               = SpeedyWeather.Leapfrog(spectral_grid).Δt
    steps_per_day    = steps_from_days(1, Δt)
    gap_steps        = round(Int, sample_hours * steps_per_day / 24) + phase_shift
    samples_per_year = round(Int, year_days * steps_per_day / gap_steps)
    n_samples        = n_years * samples_per_year

    # Sample times in days
    gap_days = gap_steps / steps_per_day
    days     = Float32.((1:n_samples) .* gap_days)



    # Grid area weights, so every global mean is area weighted
    w = area_weights(spectral_grid)

    # Containers: NaN until written, so a blow-up leaves NaN behind
    #   - global_mean: (sample, layer, traj)           the drift curve
    #   - year_mean:   (year, gridpoint, layer, traj)  one time-mean map per completed year
    global_mean = map(n_layers -> fill(NaN32, n_samples, n_layers, n_traj), probe_layers)
    year_mean   = map(n_layers -> fill(NaN32, n_years, npoints, n_layers, n_traj), probe_layers)

    # Sample at which every trajectory stopped (n_samples if it survived the whole run)
    survived = fill(n_samples, n_traj)





    ### Main loop: one long trajectory per restart
    for (i_traj, (run, season)) in enumerate(restarts)

        # Fresh simulation, loaded with the restart state (run, season)
        sim = initialize!(model_type(spectral_grid; longwave_radiation = scheme))
        restart_from!(sim, restart_state(restart_scheme, restart_unit, run, season), 0)

        # Optional perturbation (for noise floor run), seeded by the restart state
        fac_pert_T > 0 && perturb_grid_field!(sim, :temperature; fac_add = fac_pert_T, rng = Random.Xoshiro(seed + 100*run + season))

        # Start the time stepping (leapfrog start + implicit operators built from the loaded state)
        spinup_leapfrog!(sim; total_steps = n_samples * gap_steps)


        # Running sums of the current year, one (gridpoint, layer) matrix per probe
        year_sum = map(n_layers -> zeros(Float32, npoints, n_layers), probe_layers)


        # Loop over samples
        for l in 1:n_samples

            # Propagate one sampling gap
            sim_timesteps!(sim, gap_steps)

            # Stop this trajectory and warn user if the run blew up, everything after stays NaN
            if !isfinite(sum(SpeedyWeather.get_step(sim.variables.grid.temperature)))
                survived[i_traj] = l - 1
                @warn "Climate rollout $(i_traj) (restart state ($(run), $(season))) went non-finite at day $(round(days[l], digits=1)) - trajectory stopped."
                break
            end


            # Loop over probed fields
            for (p, probe) in pairs(probes)

                # Extract probe from the run
                probe_field = probe.func(sim.variables)

                # Loop over layers (all layers for profiles, one pass for scalars)
                for k in 1:probe_layers[p]

                    # Extract layer k
                    x = get_layer(probe_field, k)

                    # Global mean of this sample - the drift curve
                    global_mean[p][l, k, i_traj] = wmean(x, w)

                    # Accumulate towards the mean of the current year
                    @views year_sum[p][:, k] .+= x
                end
            end


            # Year completed: store its mean and reset the running sums
            if l % samples_per_year == 0
                year = l ÷ samples_per_year
                for p in keys(probes)
                    year_mean[p][year, :, :, i_traj] .= year_sum[p] ./ samples_per_year
                    year_sum[p] .= 0
                end
            end
        end

        # Print information about the completed trajectory
        @info "Climate rollout $(i_traj)/$(n_traj) finished! (restart state ($(run), $(season)), survived $(round(days[max(survived[i_traj],1)], digits=1)) days)"
    end



    # Collect everything (everything per trajectory, no metric applied yet - evaluation does that)
    return (;
        # Identity
        leg           = :climate,
        spectral_grid = spectral_grid,
        probes        = keys(probes),

        # Start states
        restart_scheme, restart_unit,
        fac_pert_T,

        # Time axis (samples)
        gap_days         = Float32(gap_days),       # days between two samples
        year_days        = year_days,               # length of one averaging year in days
        samples_per_year = samples_per_year,        # samples per yearly mean
        n_years          = n_years,                 # number of yearly means
        days             = days,                    # (n_samples,) time of every sample

        # Trajectory axis
        traj_run         = [run for (run, season) in restarts],       # (n_traj,) restart run of every trajectory
        traj_season      = [season for (run, season) in restarts],    # (n_traj,) restart season of every trajectory
        survived_samples = survived,                        # (n_traj,) last finite sample (= n_samples if stable)
        survived_days    = Float32.(survived .* gap_days),  # (n_traj,)

        # Global-mean time series (drift): each (n_samples, layer, n_traj), NaN after a blow-up
        global_mean,

        # Yearly mean maps: each (n_years, npoints, layer, n_traj), NaN for years not completed
        year_mean,
    )
end










### 4) Helpers

# Extract layer k of a SW field (shape: (npoints, nlayers)), a scalar field is returned as it is
get_layer(f::AbstractVector, k) = f
get_layer(f::AbstractMatrix, k) = view(f, :, k)


