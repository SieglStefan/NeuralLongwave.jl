### Restart States
###
### Functions for generating restart states with equilibrium climates
###
### A restart state is identified by (run, season):
###     - run:      one trajectory of the spinup raw data (an independent equilibrated climate)
###     - season:   one of the n_keep states taken from the last year of that run (stride samples apart)





# Extract restart states from pre-generated raw data
function derive_restart_states(;
    raw_dir,            # directory containing the spinup raw data
    scheme,             # scheme folder for storing restart states
    unit,               # unit folder for storing restart states
    runs,               # raw data trajectories used as runs (run number = trajectory number)
    n_keep = 13,        # 52 / 13 is exactly 4 weeks -> n_keep = 13 is exactly one year
    stride = 4,         # 4 weeks distance between restart states
)

    # Create output folder
    dir = prepare_out_dir(restart_states_dir(scheme, unit), overwrite=true)


    # Model date of every stored state, for picking by season
    dates = String[]

    # Loop over runs
    for run in runs

        # Open raw data
        with_raw_data(raw_dir, run) do d

            # Loop over the last n_keep states to extract restart states
            for (season, i) in enumerate(d.n_states-stride*n_keep : stride : d.n_states-1)

                # Save state
                s = d[i]
                save(s; dir, file = restart_file(run, season))

                # Store the date of the saved state
                push!(dates, string(s.prognostic.clock.time))
            end
        end
    end

    # Write info and print log
    write_info(; dir, source = raw_dir, runs = collect(runs), n_keep, dates, stride)
    @info "Restart states derived from $(raw_dir) stored at $(dir)!"

    return nothing
end



# Filename of one restart state
restart_file(run, season) = "run_$(lpad(run,2,'0'))_s$(lpad(season,2,'0')).jld2"

# Load one restart state
restart_state(scheme, unit, run, season) = load(; dir = restart_states_dir(scheme, unit), file = restart_file(run, season))
