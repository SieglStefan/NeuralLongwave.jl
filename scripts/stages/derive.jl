### Stage: derive
###
### Objective: Turn raw data into derived artifacts (the heavy steps that used to run inside 
### the evaluation/set_<SCHEME> notebooks - the notebooks now only load and plot the results)
###     - target series only: the scheme is the group (e.g. OBLW), the raw data is data/raw_data/<SCHEME>/<series>/
###
### Steps (a task lists them in steps, they run in that order):
###     - :restart_states   restart states (run, season) of the spinup     -> data/restart_states/<SCHEME>/<restart_unit>/
###     - :global_means     global mean time series of every trajectory    -> results/<SCHEME>/<unit>/global_means.jld2
###     - :rmse_caps        RMSE between all trajectory pairs + saturation -> results/<SCHEME>/<unit>/distances.jld2, rmse_caps.jld2
###     - :error_growth     RMSE between the trajectory pairs of several raw units -> results/<SCHEME>/<unit>/distances.jld2
###     - :column_io        column inputs/outputs for offline training     -> data/column_io/<SCHEME>/<column_io_unit>/
###     - :zscore           zscore statistics + output form fits           -> data/zscore/<SCHEME>/<zscore_unit>/





# Steps that store analysis results in results/<SCHEME>/<unit>/ (the others store data in data/)
is_analysis_step(step) = step in (:global_means, :rmse_caps, :error_growth)



function stage_derive(c, job)

    # Scheme of the raw data and the raw data folder of this series
    scheme  = job.group
    raw_dir = raw_data_dir(scheme, job.series, c.raw_unit)

    # Results folder of the analysis steps (only created if one of them runs)
    out_dir = reference_dir(scheme, c.unit)
    has_analysis = any(is_analysis_step, c.steps)
    has_analysis && prepare_out_dir(out_dir; overwrite = c.overwrite)


    # Run every step in the given order
    for step in c.steps

        @info "Derive step :$(step) of $(scheme) / $(job.series) / $(c.unit)"

        if step === :restart_states

            # Restart states (run, season) with equilibrium climates, every trajectory of the spinup is one run
            derive_restart_states(; raw_dir, scheme, unit = c.restart_unit,
                                    runs = c.trajs, n_keep = c.n_keep, stride = c.stride)

        elseif step === :global_means

            # Global mean time series of every trajectory (spinup drift)
            means = [global_means(raw_dir, traj; probes = c.probes) for traj in c.trajs]
            NeuralLongwave.save(means; dir = out_dir, file = "global_means.jld2")

        elseif step === :rmse_caps

            # RMSE between every pair of trajectories, and its saturated value (zero skill)
            distances = [traj_distance(raw_dir, raw_dir, a, b; probes = c.probes) for a in c.trajs for b in c.trajs if a < b]
            caps      = rmse_caps(distances, c.probes; day_min = c.day_min)
            NeuralLongwave.save(distances; dir = out_dir, file = "distances.jld2")
            NeuralLongwave.save(caps;      dir = out_dir, file = "rmse_caps.jld2")

        elseif step === :error_growth

            # RMSE between the trajectory pairs of every raw unit (repetitions of perturbed restarts)
            dirs      = [raw_data_dir(scheme, job.series, raw_unit) for raw_unit in c.raw_units]
            distances = [traj_distance(d, d, a, b; probes = c.probes) for d in dirs for a in c.trajs for b in c.trajs if a < b]
            NeuralLongwave.save(distances; dir = out_dir, file = "distances.jld2")

        elseif step === :column_io

            # Column inputs and outputs of the raw data (offline training data)
            derive_column_io(; raw_dir, scheme, unit = c.column_io_unit, trajs = c.trajs)

        elseif step === :zscore

            # Output form fits per column, then zscore statistics of the fields and the fitted coefficients
            column_io = NeuralLongwave.load(; dir = column_io_dir(scheme, c.column_io_unit), file = "column_io.jld2")
            coeffs    = map(form -> fit_coeffs(form, column_io), c.zscore_forms)
            derive_zscore(; column_io, coeffs, scheme, unit = c.zscore_unit, fit_forms = c.zscore_forms)

            # The per-column fits, for the histograms of the zscore notebook
            NeuralLongwave.save(coeffs; dir = zscore_dir(scheme, c.zscore_unit), file = "coeffs.jld2")

        else
            error("Unknown derive step :$(step) - see scripts/defaults/derive.jl")
        end
    end



    # Info file of the analysis results
    has_analysis && write_info(;
        dir        = out_dir,
        job        = job,
        provenance = provenance(),
        source     = raw_dir,
        config     = merge(c, (; zscore_forms = [string(nameof(typeof(f))) for f in c.zscore_forms])),
    )

    return nothing
end
