### Raw Data Generation
###
### Generates and stores full simulation data for derive_ and functions to access and process
###         - 1) Raw data generation functions
###         - 2) Raw data utilities










### 1) Raw data generation functions

# Generates raw data (approx. 1 full state every day for sim_days) and stores it as ic_XX.jld2
function generate_raw_data(;
    ic_nr,          # initial condition number (used for naming the file)
    data_type,      # data type
    dir,            # directory to store the raw data files
    seed,           # seed used for RNG
    
    spectral_grid,  # spectral grid
    model_type,     # used model (e.g. PrimitiveWetModel)
    lw_scheme,      # used LW parameterization scheme (e.g. OneBandLongwave)
    
    t_spinup,       # spinup time in Days (e.g. Days(10))
    start_date,     # starting date of the simulation if no restart is provided

    restart_scheme, # scheme used for the restart state
    restart_unit,   # unit used for the restart state
    restart_ic,     # specific restart IC
    restart_j,      # specific restart season

    sample_hours,   # nominal sampling cadence in hours (24 = one state per day)
    phase_shift,    # shift of steps from the nominal cadence (precession through the diurnal cycle)
    sim_days,       # number of sampled days
    offset_hours,   # offset in hours for the first state

    fac_pert_T,     # additive perturbation factor for temperature
    fac_pert_q,     # multiplicative perturbation factor for humidity
)

    # Set seed for reproducibility
    Random.seed!(seed)


    # Define model and initialize simulation
    sim = initialize!(model_type(spectral_grid; longwave_radiation = lw_scheme))


    if isnothing(restart_scheme) || isnothing(restart_unit)
        # Start from default SW initial condition
        clock_start = start_date - t_spinup
        SpeedyWeather.set!(sim.variables.prognostic.clock; time=clock_start, start=clock_start)
    else
        # Restart IC and season, a vector assigns one per IC and is cycled
        i = restart_ic isa AbstractVector ? restart_ic[mod1(ic_nr, length(restart_ic))] : restart_ic
        j = restart_j isa AbstractVector ? restart_j[mod1(ic_nr, length(restart_j))] : restart_j

        restart_from!(sim, restart_state(restart_scheme, restart_unit, i, j), 0)
    end


    # Perturb grid fields
    perturb_grid_field!(sim, :temperature; fac_add  = fac_pert_T)
    perturb_grid_field!(sim, :humidity;    fac_mult = fac_pert_q, zeromin = true)

    # Spinup simulation
    run!(sim, period = t_spinup)


    # Extract time step and calculate steps per day and offset in steps
    (; Δt) = sim.model.time_stepping
    steps_per_day = steps_from_days(1, Δt)
    offset_steps = steps_from_days(offset_hours / 24f0, Δt)

    # Calculate sampling gap steps: nominal cadence plus the precession shift
    #   - sample_hours = 24, phase_shift =  0  ->  exactly daily
    #   - sample_hours =  8, phase_shift =  0  ->  exactly 3x per day
    #   - sample_hours = 24, phase_shift = -1  ->  ~daily, precessing through the diurnal cycle
    gap_steps = round(Int, sample_hours * steps_per_day / 24) + phase_shift


    # Initialize simulation (run! unscales vorticity/divergence) and perform the first steps
    spinup_leapfrog!(sim; total_steps = sim_days * steps_per_day + offset_steps)


    # Calculate number of states (1 state = 1 full simulation.variables)
    n_states = (sim_days * steps_per_day) ÷ gap_steps + 1


    # Provide filepath
    filepath = joinpath(dir, "ic_$(lpad(ic_nr,2,'0')).jld2")

    # Sample the simulation, one full state per simulated day
    JLD2.jldopen(filepath, "w") do store
        
        # Offset the simulation by offset_steps
        sim_timesteps!(sim, offset_steps)

        # Re-linearize the semi-implicit operators AT sample 0, so a rollout restarting there
        # reproduces this run exactly (spinup_leapfrog! built them offset_steps too early)
        force_reinitialize!(sim)

        # Store first inital day
        store["s_0"] = SpeedyWeather.materialize_views(sim.variables)       # materialize_views converts a "view" into an array (here for storing)

        # Loop over the whole simulation 
        for state in 1:n_states-1

            # Propagate simulation for gap_steps steps and store variables
            sim_timesteps!(sim, gap_steps)
            store["s_$(state)"] = SpeedyWeather.materialize_views(sim.variables)
        end


        # Store general information
        store["ic_nr"]         = ic_nr
        store["data_type"]     = data_type

        # Store spectral grid, model and scheme information for rebuilding
        store["spectral_grid"] = spectral_grid
        store["model_type"]    = model_type
        store["lw_scheme"]     = lw_scheme

        # Store other useful metadata (arguments)
        store["sample_hours"]  = sample_hours
        store["phase_shift"]   = phase_shift
        store["sim_days"]      = sim_days
        store["offset_hours"]  = offset_hours

        # Store other useful metadata (derived)
        store["n_states"]      = n_states
        store["steps_per_day"] = steps_per_day
        store["gap_steps"]     = gap_steps
        store["offset_steps"]  = offset_steps
    end


    # Print info message
    @info "Raw dataset IC $(ic_nr) stored at $(dir)!"

    return nothing
end










### 2) Raw data utilities

# Struct for raw data handling
struct RawData{S}
    store::S

    ic_nr::Int
    data_type::Symbol

    spectral_grid::SpeedyWeather.SpectralGrid
    model_type::Type{<:SpeedyWeather.AbstractModel}
    lw_scheme::SpeedyWeather.AbstractLongwave

    sample_hours::Float32
    phase_shift::Int
    sim_days::Int
    offset_hours::Float32

    n_states::Int
    steps_per_day::Int
    gap_steps::Int
    offset_steps::Int
end

# Indexing utility function
Base.getindex(d::RawData, j::Integer) = d.store["s_$(j)"]


# Utility wrapper for opening a raw data file and passing it to a function (then closing automatically)
function with_raw_data(fn, dir::String, ic::Integer)

    # Open data file
    return JLD2.jldopen(joinpath(dir, "ic_$(lpad(ic,2,'0')).jld2"), "r") do store

        # Apply function (provided e.g. by fn: d -> body of a do block)
        fn(RawData{typeof(store)}(
            store, 
            store["ic_nr"],
            store["data_type"],
            store["spectral_grid"],
            store["model_type"],
            store["lw_scheme"],
            store["sample_hours"],
            store["phase_shift"],
            store["sim_days"],
            store["offset_hours"],
            store["n_states"],
            store["steps_per_day"],
            store["gap_steps"],
            store["offset_steps"]
        ))
    end
end
