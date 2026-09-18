### Test of a generated raw dataset
###
### Checks that a stored raw dataset can be read back and is self-consistent:
###     - metadata is present and matches the data_type rules
###     - the stored states are all there and can be loaded
###     - the stored recipe rebuilds a working simulation
###     - a stored state can be copied into that simulation
###
### Run from the repo root:
###     julia --project=. tests/test_raw_data.jl OBLW_00_test/training



using NeuralParam
using SpeedyWeather





### Dataset to check (first argument, or the test dataset)
RAW = length(ARGS) >= 1 ? ARGS[1] : "OBLW_00_test/training"
IC  = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 1

println("Checking raw dataset '$(RAW)', IC $(IC)\n")

fails = String[]
check(ok, msg) = (println(ok ? "  ok    $(msg)" : "  FAIL  $(msg)"); ok || push!(fails, msg))





NeuralParam.with_raw_data(RAW, IC) do d

    ### Metadata
    println("Metadata")
    println("  data_type     = ", d.data_type)
    println("  n_states      = ", d.n_states)
    println("  steps_per_day = ", d.steps_per_day)
    println("  gap_steps     = ", d.gap_steps)
    println("  offset_steps  = ", d.offset_steps)
    println("  trunc         = ", d.spectral_grid.trunc,
            "   nlayers = ", d.spectral_grid.nlayers,
            "   npoints = ", d.spectral_grid.npoints)
    println("  model         = ", d.model)
    println("  lw_scheme     = ", nameof(typeof(d.lw_scheme)))
    println()


    ### Consistency of the sampling metadata
    println("Sampling")
    check(d.ic == IC, "stored ic matches the file name")
    check(d.n_states > 1, "more than one state stored")
    check(0 <= d.offset_steps < d.steps_per_day, "offset is inside one day")

    if d.data_type === :evaluation
        check(d.gap_steps == d.steps_per_day, "evaluation data is sampled exactly daily")
    elseif d.data_type === :training
        g = gcd(d.gap_steps, d.steps_per_day)
        check(g == 1, "training gap is coprime with steps_per_day (visits all $(d.steps_per_day) phases)")
    else
        check(false, "known data_type")
    end
    println()


    ### Every state is readable
    println("States")
    ok = true
    for j in 0:d.n_states-1
        try
            d[j]
        catch
            ok = false
            println("        state $(j) missing or unreadable")
        end
    end
    check(ok, "all $(d.n_states) states readable")

    s0 = d[0]
    check(:prognostic in propertynames(s0), "state holds the prognostic variables")
    check(:grid in propertynames(s0),       "state holds the grid variables")
    check(size(s0.grid.temperature, 2) == d.spectral_grid.nlayers, "state has nlayers layers")
    println()


    ### The stored recipe rebuilds a working simulation, and a state fits into it
    println("Restart")
    sim = initialize!(d.model(d.spectral_grid; longwave_radiation = d.lw_scheme))
    check(true, "model rebuilt from the stored recipe")

    copy!(sim.variables, d[0])
    check(true, "state 0 copied into the simulation")

    T0 = copy(SpeedyWeather.get_step(sim.variables.grid.temperature))
    copy!(sim.variables, d[d.n_states-1])
    T1 = SpeedyWeather.get_step(sim.variables.grid.temperature)
    check(T0 != T1, "first and last state differ (the simulation actually advanced)")
    println()
end





### Summary
if isempty(fails)
    println("All checks passed.")
else
    println("$(length(fails)) check(s) FAILED:")
    for f in fails
        println("  - ", f)
    end
    exit(1)
end
