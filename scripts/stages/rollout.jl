### Stage: rollout
###
### Objective: Roll out a scheme (emulator or baseline) for weather against a reference and/or climate
###     - experiment series:    results/<experiment>/<series>/<unit>/rollout/
###     - target series:        results/<SCHEME>/<unit>/  (reference runs of the target, baselines only)
###
### A leg runs only if its default block was stacked, and a task can switch it off
### (weather_n_starts = 0 / climate_n_years = 0, see split_tasks).





function stage_rollout(c, job)

    # Legs of this task
    do_weather = haskey(c, :weather_raw_unit) && c.weather_n_starts > 0
    do_climate = haskey(c, :climate_n_years)  && c.climate_n_years  > 0
    do_weather || do_climate || error("Neither the weather nor the climate leg runs - nothing to do!")

    # A target series only rolls out baselines (it has no trained emulators)
    job.kind === :target && isnothing(c.baseline) && error("A target series needs a baseline for every task ($(c.unit))!")


    # Set seed for reproducibility
    Random.seed!(c.seed)

    # Output folder, shared by all tasks of a unit (see split_tasks) - every task writes only its own files
    dir = mkpath(job.kind === :target ? reference_dir(job.group, c.unit) :
                                        rollout_dir(job.group, job.series, c.unit))

    # Info file of this task: one per leg (split_tasks runs weather and climate as separate tasks)
    info_file = !do_climate ? "info_weather.toml" :
                !do_weather ? "info_climate.toml" : "info.toml"

    # Refuse to replace existing files unless overwrite is set
    own_files = [info_file; do_weather ? "weather.jld2" : String[]; do_climate ? "climate.jld2" : String[]]
    existing  = filter(file -> isfile(joinpath(dir, file)), own_files)
    isempty(existing) || c.overwrite || error("Files already exist in $(dir): $(existing) - set overwrite = true")


    # Spectral grid
    spectral_grid = SpectralGrid(truncation = c.truncation, nlayers = c.nlayers)



    ### Define the to be rolled out scheme

    if isnothing(c.baseline)

        # Trained emulator of the SAME experiment/series/unit
        init_dir = emulator_dir(job.group, job.series, c.unit)
        scheme = NeuralLongwave.load(; dir = init_dir, file = "emulator.jld2")
        @info "Rolling out the trained emulator at $(init_dir)!"

    else

        # Baseline built from its recipe, every recipe takes the keys it needs from the config and ignores the rest
        scheme = build_scheme(c.baseline, spectral_grid; c...)
        @info "Rolling out the baseline :$(c.baseline)!"
    end



    ### Prepare the two legs

    # Weather leg, or nothing if it does not run
    weather_config = !do_weather ? nothing : (;
        raw_dir      = raw_data_dir(c.weather_raw_scheme, c.weather_raw_series, c.weather_raw_unit),
        trajs        = c.weather_trajs,
        probes       = c.weather_probes,
        horizon_days = c.weather_horizon_days,
        n_starts     = c.weather_n_starts,
        field_days   = c.weather_field_days,
        fac_pert_T   = c.weather_fac_pert_T,
        seed         = c.seed,
    )

    # Climate leg, or nothing if it does not run
    climate_config = !do_climate ? nothing : (;
        spectral_grid  = spectral_grid,
        model_type     = c.climate_model_type,
        restart_scheme = c.climate_restart_scheme,
        restart_unit   = c.climate_restart_unit,
        restarts       = c.climate_restarts,
        probes         = c.climate_probes,
        n_years        = c.climate_n_years,
        year_days      = c.climate_year_days,
        sample_hours   = c.climate_sample_hours,
        phase_shift    = c.climate_phase_shift,
        fac_pert_T     = c.climate_fac_pert_T,
        seed           = c.seed,
    )


    # Generate both legs of the rollout
    rollout_summary = generate_rollout(;
        dir      = dir,
        scheme   = scheme,
        weather  = weather_config,
        climate  = climate_config,
    )



    # Create and store the info file of this task
    write_info(;
        dir        = dir,
        file       = info_file,
        job        = job,
        provenance = provenance(),

        # Probes are NamedTuples of functions, so store only their names
        config = merge(c,
            do_weather ? (; weather_probes = collect(string.(keys(c.weather_probes)))) : (;),
            do_climate ? (; climate_probes = collect(string.(keys(c.climate_probes)))) : (;),
        ),

        scheme = (;
            source = isnothing(c.baseline) ? "trained" : "baseline",
            info_scheme(scheme)...,
        ),

        grid = (; grid_type = string(nameof(spectral_grid.Grid))),

        weather = !do_weather ? (; skipped = true) : (;
            n_traj       = rollout_summary.weather.n_traj,
            horizon_days = rollout_summary.weather.horizon_days,
        ),

        climate = !do_climate ? (; skipped = true) : (;
            n_traj        = rollout_summary.climate.n_traj,
            horizon_days  = rollout_summary.climate.horizon_days,
            survived_days = collect(rollout_summary.climate.survived_days),
        ),
    )

    return nothing
end
