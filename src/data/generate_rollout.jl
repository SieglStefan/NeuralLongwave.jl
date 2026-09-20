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
###     - climate:  3 years:    The run has decorrelated from the reference, so pointwise scores
###                 are meaningless. Only calculating temporal and spatial means.
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
        (; n_traj = length(w.traj_ic), horizon_days = last(w.days))
    end

    # Climate leg
    c_summary = if isnothing(climate)
        nothing
    else
        c = rollout_climate(scheme; climate...)
        save(c; dir, file = "climate.jld2")
        @info "Climate leg stored at $(dir)!"
        (; n_traj = length(c.traj_ic), horizon_days = last(c.days), survived_days = c.survived_days)
    end


    # Return a small summary for the info.toml of the run
    return (; weather = w_summary, climate = c_summary)
end










### 2) Weather leg (14 day rollouts)

# Short rollouts, scored pointwise against the reference trajectory at matched lead times
function rollout_weather(
    scheme;             # scheme to roll out
    raw_dir,            # reference raw dataset
    ic_subset,          # reference ICs to start from
    probes,             # fields the rollout is judged on
    horizon_days,       # forecast length in days
    n_starts,           # number of start states PER IC
    field_days,         # lead days for which entire fields are stored (e.g. for heatmaps)
)


    # Read reference metadata
    meta = with_raw_data(raw_dir, first(ic_subset)) do d
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
    n_traj = length(ic_subset) * n_starts



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

    # Labels of the trajectory axis, encoding every trajectory with (ic, start sample)
    traj_ic, traj_start = Int[], Int[]



    # Index counter for trajectories
    i_traj = 0

    ### Main loop: roll out every trajectory, scoring each lead sample as it is reached
    # Loop over ICs
    for ic in ic_subset
        with_raw_data(raw_dir, ic) do d

            # State the reference built its semi-implicit operators from, read once per IC
            state0 = d[0]


            # Loop over all starts (evenly distributed across a year)
            for s in starts_sampled

                # Count and label this trajectory
                i_traj += 1
                push!(traj_ic, ic)
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

                @info "Weather rollout $(i_traj)/$(n_traj) finished! (IC $(ic), start sample $(s))"
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
        traj_ic,                                      # (n_traj,) reference IC of every trajectory
        traj_start,                                   # (n_traj,) start sample of every trajectory

        # Scores: (; T = (; rmse, bias, maxdiff), olw = ...), each (horizon_samples, layer, n_traj)
        scores,

        # Full fields on selected lead days
        field_days    = Float32.(field_sampled .* gap_days),   # (n_fields,)
        field_run, field_ref,                                  # each (n_fields, npoints, layer, n_traj)
    )
end










### 3) Climate leg (3 year rollouts)

# Long rollouts, reduced to global-mean time series and time-mean fields, compared as statistics
function rollout_climate(
    scheme;               # scheme to roll out
    raw_dir,                # reference raw dataset (:climate) in data/raw_data/
    ic_subset,              # reference ICs to start from
    probes,                 # fields the rollout is judged on
    horizon_days,           # rollout length in days
    n_windows,              # number of averaging windows
)


    # Read reference metadata
    meta = with_raw_data(raw_dir, first(ic_subset)) do d
        (; d.spectral_grid, d.model_type, d.n_states, d.gap_steps, d.steps_per_day)
    end

    # Extract grid dimensions (number of grid points per state and NT of number of vertical layers per probe)
    npoints = meta.spectral_grid.npoints
    probe_layers = map(e -> e.kind === :profile ? meta.spectral_grid.nlayers : 1, probes)      # e.g. = (; T = 8, olw = 1, ...)



    # Real distance between two samples, in days
    gap_days = meta.gap_steps / meta.steps_per_day

    # Length of horizon_days in reference samples units
    #   - (e.g. horizon_days = 3*366, gap_days = 1 -> horizon_sampled = 1098)
    horizon_sampled = round(Int, horizon_days / gap_days)

    # Check that the rollout still ends inside the reference (states are d[0] ... d[n_states-1])
    horizon_sampled <= meta.n_states - 1 ||
        error("horizon $(horizon_sampled) exceeds the reference ($(meta.n_states - 1) samples)!")

    # Use every available IC as one trajectory
    n_traj = length(ic_subset)



    # As many whole windows as fit; the remainder (< window_len samples) is dropped
    window_length = horizon_sampled ÷ n_windows
    windows = [(i-1)*window_length + 1 : i*window_length for i in 1:n_windows]

    # Calculate sample times in days (e.g. gap_days = 1: [1,2,3,...] -> [1.0, 2.0, 3.0, ...])
    days = Float32.((1:horizon_sampled) .* gap_days)



    # Grid area weights, so every global mean is area weighted
    w = area_weights(meta.spectral_grid)

    # Utility functions for allocating properly shaped arrays
    curve(n_layers) = fill(NaN32, horizon_sampled, n_layers, n_traj)        # mean vs. time (spatially averaged), NaN after a blow-up
    field(n_layers) = zeros(Float32, n_windows, npoints, n_layers, n_traj)  # mean vs. grid (temporally averaged over window)



    # Create containers for storing time series and field data
    global_mean_run, global_mean_ref    = map(curve, probe_layers), map(curve, probe_layers)
    time_mean_run,   time_mean_ref      = map(field, probe_layers), map(field, probe_layers)

    # Number of samples actually accumulated per window (a run that blows up stops early)
    #   - e.g. n_acc[:, i_traj] = [53, 27, 0] -> died at sample 80
    n_acc = zeros(Int, n_windows, n_traj)

    # Sample at which every trajectory stopped (horizon_sampled if it survived the whole run)
    survived = fill(horizon_sampled, n_traj)





    ### Main loop: roll out one long trajectory per reference IC, reducing every sample as it is reached
    # Loop over trajectories
    for (i_traj, ic) in enumerate(ic_subset)
        with_raw_data(raw_dir, ic) do d


            # Fresh simulation for every trajectory
            sim = initialize!(meta.model_type(meta.spectral_grid; longwave_radiation = scheme))
            spinup_leapfrog!(sim; total_steps = horizon_sampled * meta.gap_steps)

            # Start from the reference's own start state, so run and reference share the initial climate
            restart_from!(sim, d[0], 0)


            # Loop over samples
            for l in 1:horizon_sampled

                # Propagate one reference gap and load the reference state at sample l
                sim_timesteps!(sim, meta.gap_steps)
                ref_state = d[l]

                # Stop this trajectory if the run blew up - everything after stays NaN (time series) or is discarded (windows)
                if !isfinite(sum(SpeedyWeather.get_step(sim.variables.grid.temperature)))
                    survived[i_traj] = l - 1
                    @warn "Climate rollout $(i_traj) (IC $(ic)) went non-finite at day $(round(days[l], digits=1)) - trajectory stopped."
                    break
                end

                # Averaging window this sample falls into
                iw = findfirst(r -> l in r, windows)


                # Loop over to be probed fields
                for (p, probe) in pairs(probes)

                    # Extract probe from run and reference state
                    run = probe.func(sim.variables)
                    ref = probe.func(ref_state)


                    # Loop over layers (all layers for profiles, one pass for scalars)
                    for k in 1:probe_layers[p]

                        # Extract layer k of run and reference
                        x, y = get_layer(run, k), get_layer(ref, k)

                        # Global mean of this sample - the drift curve
                        global_mean_run[p][l,k,i_traj] = wmean(x, w)
                        global_mean_ref[p][l,k,i_traj] = wmean(y, w)

                        # Accumulate towards the time mean of this window - the climate bias map
                        @views time_mean_run[p][iw,:,k,i_traj] .+= x
                        @views time_mean_ref[p][iw,:,k,i_traj] .+= y
                    end
                end

                # Count this sample towards its window
                n_acc[iw, i_traj] += 1
            end

            @info "Climate rollout $(i_traj)/$(n_traj) finished! (IC $(ic), survived $(round(days[max(survived[i_traj],1)], digits=1)) days)"
        end
    end


    # Turn the accumulated sums into time means (windows a trajectory never reached become NaN)
    for p in keys(probes), i_traj in 1:n_traj, iw in 1:n_windows
        
        # Discard windows that were not fully accumulated
        s = n_acc[iw, i_traj] == length(windows[iw]) ? Float32(n_acc[iw,i_traj]) : NaN32

        for k in 1:probe_layers[p]
            @views time_mean_run[p][iw,:,k,i_traj] ./= s
            @views time_mean_ref[p][iw,:,k,i_traj] ./= s
        end
    end


    # Collect everything (everything per trajectory, no metric applied yet - evaluation does that)
    return (;
        # Identity
        leg           = :climate,
        raw_dir       = raw_dir,
        spectral_grid = meta.spectral_grid,
        probes        = keys(probes),

        # Time axis (samples)
        gap_days        = Float32(gap_days),          # days between two reference samples
        horizon_days    = Float32(horizon_days),      # requested horizon
        horizon_samples = horizon_sampled,            # horizon actually rolled out
        days            = days,                       # (horizon_samples,) time of every sample

        # Trajectory axis (one trajectory per IC)
        traj_ic          = collect(ic_subset),              # (n_traj,)
        survived_samples = survived,                        # (n_traj,) last finite sample (= horizon_samples if stable)
        survived_days    = Float32.(survived .* gap_days),  # (n_traj,)

        # Global-mean time series (drift): each (horizon_samples, layer, n_traj), NaN after blow-up
        global_mean_run, global_mean_ref,

        # Window axis
        window_samples = window_length,                                           # samples per window
        window_ranges  = windows,                                                 # (n_windows,) sample ranges
        window_days    = [(days[first(r)], days[last(r)]) for r in windows],      # (n_windows,) (start, end) in days
        n_acc          = n_acc,                                                   # (n_windows, n_traj) samples summed per window

        # Time-mean fields per window: each (n_windows, npoints, layer, n_traj), NaN if the window was not completed
        time_mean_run, time_mean_ref,
    )
end










### 4) Helpers

# Extract layer k of a SW field (shape: (npoints, nlayers)), a scalar field is returned as it is
get_layer(f::AbstractVector, k) = f
get_layer(f::AbstractMatrix, k) = view(f, :, k)


