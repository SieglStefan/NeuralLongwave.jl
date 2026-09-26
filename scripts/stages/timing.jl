### Stage: timing
###
### Objective: Runtime of every scheme relative to the reference (the FIRST task, normally b_OBLW)
###     - experiment series only, ONE job times ALL tasks (interleaved, so they share the machine state)
###     - output: results/<experiment>/<series>/timing/





function stage_timing(configs, job)

    # Series-wide settings are taken from the first task
    c = first(configs)

    # Set seed for reproducibility
    Random.seed!(c.seed)

    # Pin BLAS to one thread (the per-column matvecs are tiny, multithreaded BLAS on them is pure noise)
    LinearAlgebra.BLAS.set_num_threads(1)
    Threads.nthreads() == 1 || @warn "Julia runs with $(Threads.nthreads()) threads - times are not comparable to 1-thread runs!"

    # Output folder of the series
    dir = mkpath(timing_dir(job.group, job.series))
    isfile(joinpath(dir, "timing.jld2")) && !c.overwrite && error("timing.jld2 already exists in $(dir) - set overwrite = true")

    # Spectral grid
    spectral_grid = SpectralGrid(truncation = c.truncation, nlayers = c.nlayers)



    # Scheme of one task: the trained emulator of the SAME experiment/series/unit, or a baseline from its recipe
    timed_scheme(cu) = isnothing(cu.baseline) ?
        NeuralLongwave.load(; dir = emulator_dir(job.group, job.series, cu.unit), file = "emulator.jld2") :
        build_scheme(cu.baseline, spectral_grid; cu...)

    # Timed schemes (unit name => scheme), the first one is the reference
    schemes = (; (Symbol(cu.unit) => timed_scheme(cu) for cu in configs)...)
    @info "Timing $(length(schemes)) units, reference :$(first(keys(schemes)))"



    # Time all schemes
    timing = generate_timing(;
        dir            = dir,
        schemes        = schemes,
        spectral_grid  = spectral_grid,
        model_type     = c.model_type,
        restart_scheme = c.restart_scheme,
        restart_unit   = c.restart_unit,
        restart        = c.restart,
        n_warmup       = c.n_warmup,
        n_sweep_rounds = c.n_sweep_rounds,
        n_step_rounds  = c.n_step_rounds,
    )

    # Quick look into the log
    print_timing(timing)



    # Create and store the info file
    write_info(;
        dir        = dir,
        job        = job,
        provenance = provenance(),
        config     = c,
        units      = [string(cu.unit) for cu in configs],
        machine    = timing.machine,
    )

    return nothing
end
