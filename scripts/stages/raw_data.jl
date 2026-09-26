### Stage: raw data
###
### Objective: Propagate a target scheme and store its full state on a fixed sampling cadence
###     - target series only: the scheme is the group (e.g. OBLW)
###     - output: data/raw_data/<SCHEME>/<series>/<unit>/





function stage_raw_data(c, job)

    # Scheme of the raw data
    scheme = job.group

    # Set seed for reproducibility
    Random.seed!(c.base_seed)

    # Create output folder - a single-trajectory task shares it with the other trajectories, so it is never cleared
    dir = isnothing(c.only_traj) ? prepare_out_dir(raw_data_dir(scheme, job.series, c.unit); overwrite = c.overwrite) :
                                   mkpath(raw_data_dir(scheme, job.series, c.unit))


    # Spectral grid
    spectral_grid = SpectralGrid(truncation = c.truncation, nlayers = c.nlayers)

    # Target scheme, every recipe takes the keys it needs from the config and ignores the rest
    target = build_scheme(c.target_type, spectral_grid; c...)



    # Generate raw data, one trajectory (file) per start state
    isempty(c.starts) && error("Raw data task $(c.unit) has no starts - list one start state per trajectory!")

    for (traj, start) in enumerate(c.starts)

        # Check if only one traj is requested
        isnothing(c.only_traj) || traj == c.only_traj || continue

        generate_raw_data(
            traj           = traj,
            start          = start,
            data_type      = c.data_type,
            dir            = dir,
            seed           = c.base_seed + traj,

            spectral_grid  = spectral_grid,
            model_type     = c.model_type,
            lw_scheme      = target,

            t_spinup       = c.t_spinup,
            start_date     = c.start_date,

            restart_scheme = c.restart_scheme,
            restart_unit   = c.restart_unit,

            sample_hours   = c.sample_hours,
            phase_shift    = c.phase_shift,
            sim_days       = c.sim_days,
            offset_hours   = c.offset_hours * (traj - 1),

            fac_pert_T     = c.fac_pert_T,
            fac_pert_q     = c.fac_pert_q,
        )
    end



    # Create and store info.toml file
    write_info(;
        dir        = dir,
        file       = isnothing(c.only_traj) ? "info.toml" : "info_traj_$(lpad(c.only_traj, 2, '0')).toml",
        job        = job,
        provenance = provenance(),
        config     = c,
        target     = (; info_scheme(target)...),
        grid       = (; grid_type = string(nameof(spectral_grid.Grid))),
    )

    return nothing
end
