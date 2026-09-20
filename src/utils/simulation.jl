### Simulation utilities
###
### General helper functions for handling SpeedyWeather simulations
###         - 1) Perturbation and time stepping
###         - 2) Simulation (re-)starting
###         - 3) Conversion Helpers










### 1) Perturbation and time stepping

# Perturbate a grid variable of a simulation by applying white noise
function perturb_grid_field!(
    sim,                            # simulation to be perturbed
    var::Symbol;                    # to be perturbed variable
    fac_add = 0f0,                  # additive perturbation factor
    fac_mult = 0f0,                 # multiplicative perturbation factor
    offset = 0f0,                   # offset to be added to the field
    zeromin = false,                # whether to set negative values to zero
    rng = Random.default_rng()      # used RNG
)
    
    # Check if grid has variable var
    if !hasfield(typeof(sim.variables.grid), var)
        @warn "Field $var does not exist in used model — perturbation skipped!." maxlog=1
        return nothing
    end

    # Initalize simulation (fill variables.grid if not initialized yet, could be empty)
    SpeedyWeather.initialize!(sim, steps=0)

    # Copy (current) field for perturbation
    field = copy(SpeedyWeather.get_step(getfield(sim.variables.grid, var)))


    # Additive perturbation
    field .+= fac_add .* randn!(rng, similar(field))

    # Multiplicative perturbation
    field .*= 1f0 .+ fac_mult .* randn!(rng, similar(field))

    # Offset
    field .+= offset

    # Only take positive values if set
    if zeromin
        field .= max.(field, 0f0)
    end


    # Apply perturbed field to simulation (transform to spectral space and then set as prognostic variables, grid variables remain stale)
    SpeedyWeather.set!(sim; var => field)

    # XXX OLD: Initialize simulation (transform previously set prognostic vars to grid space and set grid variables)
    # XXX OLD: SpeedyWeather.initialize!(sim, steps=0)
    # Transform prognostic variables to grid variables and set them
    SpeedyWeather.transform!(sim.variables, sim.model, initialize = true)

    return nothing
end



# Propagate a simulation for n_steps
function sim_timesteps!(sim, n_steps)

    # Propagate the simulation for n_steps
    for _ in 1:n_steps
        SpeedyWeather.time_step!(sim.variables, sim.model.time_stepping, sim.model)             # propagate dynamics
        SpeedyWeather.time_step!(sim.variables.prognostic.clock, sim.model.time_stepping)       # propagate clock
    end

    return nothing
end










### 2) Simulation (re-)starting

# Initialize a simulation and spinup leapfrog (do two first steps Δt/2 -> Δt -> 2*Δt)
function spinup_leapfrog!(sim; total_steps = 0)

    # Initialize simulation
    SpeedyWeather.initialize!(sim, steps=total_steps+2)

    # Spinup leapfrog
    for _ in 1:2
        SpeedyWeather.time_step!(sim)
    end

    # Reinitialize simulation (rebuilding model.implicit operators with leapfrog timestep 2*Δt)
    SpeedyWeather.reinitialize!(sim.model, sim.variables)

    return sim
end



# Force the implicit operators to be rebuilt from the current state
#   (reinitialize! checks if implicit.Δt = current Δt, without setting implicit.Δt = 0 
#   rebuilding implicit operators would be skipped and therefore defined wrong)
function force_reinitialize!(sim)
    
    # Set implicit timestep to zero to force rebuilding
    sim.model.implicit.Δt[] = 0

    # Reinitailize simulation to rebuild semi-implicit operators
    SpeedyWeather.reinitialize!(sim.model, sim.variables)

    return nothing
end



# Restart a simulation from a stored state and propagate it n_steps
function restart_from!(sim, vars0, n_steps)
    
    # Copy variables from reference variables vars0
    copy!(sim.variables, vars0)

    # Rebuild semi-implicit operators from the current state (otherwise the old reference state is used)
    force_reinitialize!(sim) 

    # Propagate simulation for n_steps
    sim_timesteps!(sim, n_steps)

    return sim
end










### 3) Conversion Helpers

# Calculate the number of timesteps from a number of days
steps_from_days(days, Δt_sec) = round(Int, days *86400 /Δt_sec)

# Calculate the number of days from a number of timesteps
days_from_steps(n_steps, Δt_sec) = n_steps *Δt_sec /86400



# Conversion factor from fluxes to temperature tendencies
function flux_to_dT_fac(model)

    # Extract model parameters
    disgma = model.geometry.vertical_coordinates.σ_thickness
    g = model.planet.gravity
    cp = model.atmosphere.heat_capacity

    # Return factor
    return g ./ (cp .* disgma)
end