### Restart States
###
### Functions for generating restart states with equilibrium climates





# Extract restart states from pre-generated raw data
function derive_restart_states(; 
    raw_dir,            # directory containing raw data
    scheme,             # scheme folder for storing restart states
    unit,               # unit folder for storing restart states
    ic_subset,          # initial conditions to process from raw data 
    n_keep = 13,        # 52 / 13 is exactly 4 weeks -> n_keep = 13 is exactly one year
    stride = 4,         # 4 weeks distance between restart states
)

    # Create output folder
    dir = prepare_out_dir(restart_states_dir(scheme, unit), overwrite=true)

    
    # Model date of every stored state, for picking by season
    dates = String[]

    # Loop over initial conditions
    for ic in ic_subset

        # Open raw data
        with_raw_data(raw_dir, ic) do d

            # Loop over the last n_keep states to extract restart states
            for (j, i) in enumerate(d.n_states-stride*n_keep : stride : d.n_states-1)
                
                # Save state
                s = d[i]
                save(s; dir, file = restart_file(ic, j))

                # Store the date of the saved state
                push!(dates, string(s.prognostic.clock.time))
            end
        end
    end

    # Write info and print log
    write_info(; dir, source = raw_dir, ic_subset = collect(ic_subset), n_keep, dates, stride)
    @info "Restart states derived from $(raw_dir) stored at $(dir)!"

    return nothing
end



# Filename of one restart state
restart_file(ic, j) = "ic_$(lpad(ic,2,'0'))_s$(lpad(j,2,'0')).jld2"

# Load one restart state
restart_state(scheme, unit, ic, j) = load(; dir = restart_states_dir(scheme, unit), file = restart_file(ic, j))
