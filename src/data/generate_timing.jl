### Timing generation
###
### Measures the runtime of several longwave schemes on the same machine, later printed by evaluation
###         - 1) Timing Wrapper
###         - 2) Helpers
###
### Two numbers per scheme, both in ms:
###     - sweep:    one parameterization! call per grid column, i.e. the pure cost of the scheme.
###     - step:     one full SpeedyWeather timestep with the scheme plugged in
###
### Reproducibility:
###     - all schemes are timed in ONE job, interleaved sample by sample (randomized order)
###     - the raw samples are stored, the summary (min, median, ratio to the reference) is done in evaluation
###     - the ratios are robust without an exclusive node (check the noise column)










### 1) Timing Generation

# Time the sweep and the full step of every scheme and store the raw samples as timing.jld2
function generate_timing(;
    dir,                    # output folder, results/<experiment>/<series>/timing
    schemes,                # NamedTuple of schemes (unit names), the first one is the reference
    spectral_grid,          # used spectral grid
    model_type,             # SW model (e.g. PrimitiveWetModel)
    restart_scheme,         # scheme folder of the restart state all schemes start from
    restart_unit,           # specific restart unit within the restart folder
    restart,                # (run, season) restart state all schemes start from
    n_warmup,               # untimed calls per scheme before timing (compilation+caches)
    n_sweep_rounds,         # timed sweeps per scheme (default 1000)
    n_step_rounds,          # timed full steps per scheme (default 200)
)


    # Load specified restart state
    state0 = restart_state(restart_scheme, restart_unit, restart...)

    # Initialize simulations of all schemes (target + emulators) and do a first initial step
    sims = map(schemes) do scheme
        sim = initialize!(model_type(spectral_grid; longwave_radiation = scheme))
        restart_from!(sim, state0, 2)
    end

    # Extract numper of grid points
    npoints = spectral_grid.npoints


    # Warmup every simulation: compile everything and fill the caches before anything is timed
    for sim in sims
        for _ in 1:n_warmup
            sweep!(sim, npoints)
            sim_timesteps!(sim, 1)
        end
    end

    # Measure the memory allocations of one sweep for each scheme
    sweep_bytes = map(sim -> @allocated(sweep!(sim, npoints)), sims)


    # Time the sweeps and full steps for each scheme, interleaved over the schemes
    sweep_ms = time_interleaved(sim -> sweep!(sim, npoints), sims, n_sweep_rounds)
    step_ms  = time_interleaved(sim -> sim_timesteps!(sim, 1), sims, n_step_rounds)


    # Machine metadata, absolute times only mean something together with this
    # Collect machine metadata
    machine = (;
        host          = gethostname(),                              # computer/machine name
        cpu           = Sys.CPU_NAME,                               # used cpu (e.g. znver3 = AMD Zen 3)
        julia_threads = Threads.nthreads(),                         # number of Julia threads
        blas_threads  = LinearAlgebra.BLAS.get_num_threads(),       # nr. of threads used by linear algebra libraries (BLAS)
        slurm_job     = get(ENV, "SLURM_JOB_ID", ""),
    )

    # Store the unit data and meta data
    units = map((sweep, step, bytes) -> (; sweep_ms = sweep, step_ms = step, sweep_bytes = bytes), sweep_ms, step_ms, sweep_bytes)
    timing = (; units, npoints, machine)
    save(timing; dir, file = "timing.jld2")
    @info "Timing stored at $(dir)!"

    return timing
end










### 2) Helpers

# One sweep (whole global grid) of parameterization! calls
#   - "@noinline" to prevent the compiler from inlining (copying) the function
@noinline function sweep!(sim, npoints)

    # Shortcut variables
    vars, model = sim.variables, sim.model
    scheme = model.longwave_radiation

    # Call the parameterization for the whole global grid
    for ij in 1:npoints
        SpeedyWeather.parameterization!(ij, vars, scheme, model)
    end

    return nothing
end



# Time f(sim) for every simulation in sims for n_rounds times, interleaved
#   - order of sims is randomized
function time_interleaved(f, sims, n_rounds)

    # NamedTuple of all timing samples per scheme
    samples = map(_ -> zeros(Float64, n_rounds), sims)
    n_schemes = length(sims)

    # Run garbage collecter once before starting the timing
    GC.gc()

    # All specified rounds (e.g. 1000 for sweep)
    for r in 1:n_rounds

        # Loop over all schemes for this round
        for i in 1:n_schemes

            # Rotated order: round 1 starts at scheme 1, round 2 at scheme 2, ...
            #   - mod1(x,3) gives remainder of a/b in form 1,2,3 instead of 1,2,0 (mod)
            k = mod1(i + r - 1, n_schemes)


            # Clean up garbage before the call (untimed) and switch the GC off during it
            # (so no garbage-collection pause lands inside the measured time)
            GC.gc(false)
            GC.enable(false)

            # Time one call
            t0 = time_ns()
            f(sims[k])
            t1 = time_ns()

            # Switch the GC back on
            GC.enable(true)


            # Store timing in milliseconds
            samples[k][r] = (t1 - t0) / 1e6
        end
    end

    return samples
end
