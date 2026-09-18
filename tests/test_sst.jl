### Restart round-trip test
###
### Checks that restart_from! restores every SLOW reservoir - above all the SlabOcean
### SST, which carries the 10-year spinup. If SST silently reverts on restart, every
### equilibrated start state is worthless and the whole spinup is wasted.
###
### Run from the repo root:
###     julia --project=. tests/test_sst.jl

using NeuralParam
using SpeedyWeather
using Statistics

const RAW = "OBLW_02_spinup/restart_states"
const IC  = 1
const J   = 120                       # an equilibrated state (day ~3457)


# Plain array behind a field-like object
raw(x) = x isa AbstractArray ? x : (hasproperty(x, :data) ? x.data : nothing)

# Largest absolute difference, NaN if the shapes do not match
function maxdiff(a, b)
    (a === nothing || b === nothing) && return NaN
    size(a) == size(b) || return NaN
    return maximum(abs.(vec(a) .- vec(b)))
end

# Report one field: shapes on both sides plus the difference after restart
function report(name, xa, xb)
    ra, rb = raw(xa), raw(xb)
    d = maxdiff(ra, rb)

    flag = isnan(d) ? "SHAPE MISMATCH" : (d == 0 ? "ok" : "DIFFERS")
    println("    ", rpad(name, 34),
            rpad(string(ra === nothing ? "-" : size(ra)), 14),
            rpad(string(rb === nothing ? "-" : size(rb)), 14),
            lpad(isnan(d) ? "-" : string(round(d, sigdigits = 4)), 12), "  ", flag)
end


NeuralParam.with_raw_data(RAW, IC) do d

    println("dataset  : ", RAW, "  ic = ", IC)
    println("n_states : ", d.n_states, "   gap_steps = ", d.gap_steps,
            "  (", round(d.gap_steps / d.steps_per_day, digits = 2), " days per state)")

    sim = initialize!(d.model(d.spectral_grid; longwave_radiation = d.lw_scheme))
    NeuralParam.first_steps!(sim; planned_steps = 4 * d.gap_steps)

    ref, prev = d[J], d[J-1]


    ### 0. Non-vacuity - consecutive stored states must actually differ in SST
    sst_r = raw(ref.prognostic.ocean.sea_surface_temperature)
    sst_p = raw(prev.prognostic.ocean.sea_surface_temperature)

    println("\n[0] SST evolves between stored states j-1 and j")
    println("    max|dSST| = ", round(maxdiff(sst_r, sst_p), sigdigits = 4), " K",
            "     mean SST = ", round(mean(Float64.(sst_r)), digits = 4), " K")


    ### 1. Restart, then compare the slow reservoirs
    NeuralParam.restart_from!(sim, ref, 0)
    p = sim.variables.prognostic

    println("\n[1] Slow reservoirs after restart_from!")
    println("    ", rpad("field", 34), rpad("sim", 14), rpad("stored", 14), lpad("max|diff|", 12))

    report("ocean.sea_surface_temperature", p.ocean.sea_surface_temperature, ref.prognostic.ocean.sea_surface_temperature)
    report("ocean.sea_ice_concentration",   p.ocean.sea_ice_concentration,   ref.prognostic.ocean.sea_ice_concentration)
    report("land.soil_temperature",         p.land.soil_temperature,         ref.prognostic.land.soil_temperature)
    report("land.soil_moisture",            p.land.soil_moisture,            ref.prognostic.land.soil_moisture)
    report("land.snow_depth",               p.land.snow_depth,               ref.prognostic.land.snow_depth)


    ### 2. Spectral dynamics - materialize_views may drop the leapfrog step dimension
    println("\n[2] Spectral prognostics (step dimension)")
    for nm in (:vorticity, :divergence, :temperature, :humidity, :pressure)
        report(string(nm), getproperty(p, nm), getproperty(ref.prognostic, nm))
    end


    ### 3. The clock - the solar zenith angle depends on it
    tc, tr = p.clock.time, ref.prognostic.clock.time
    println("\n[3] Clock:  stored = ", tr, "   after restart = ", tc,
            "   ", tc == tr ? "ok" : "DIFFERS")


    ### 4. Does the restored state survive perturbation?
    #   perturb_grid_field! calls SpeedyWeather.initialize!(sim, steps=0) internally.
    #   If that resets prognostics to the model's ICs, SST silently reverts to
    #   climatology and the whole 10-year spinup is thrown away.
    NeuralParam.restart_from!(sim, ref, 0)

    T_before = copy(raw(SpeedyWeather.get_step(sim.variables.grid.temperature)))

    NeuralParam.perturb_grid_field!(sim, :temperature; fac_add  = 2f0)
    NeuralParam.perturb_grid_field!(sim, :humidity;    fac_mult = 0.2f0, zeromin = true)

    p2 = sim.variables.prognostic
    T_after = raw(SpeedyWeather.get_step(sim.variables.grid.temperature))

    println("\n[4] Slow reservoirs after restart_from! + perturb_grid_field!")
    println("    ", rpad("field", 34), rpad("sim", 14), rpad("stored", 14), lpad("max|diff|", 12))

    report("ocean.sea_surface_temperature", p2.ocean.sea_surface_temperature, ref.prognostic.ocean.sea_surface_temperature)
    report("ocean.sea_ice_concentration",   p2.ocean.sea_ice_concentration,   ref.prognostic.ocean.sea_ice_concentration)
    report("land.soil_temperature",         p2.land.soil_temperature,         ref.prognostic.land.soil_temperature)
    report("land.soil_moisture",            p2.land.soil_moisture,            ref.prognostic.land.soil_moisture)

    println("\n    non-vacuity: the perturbation must actually have landed")
    println("    max|dT| = ", round(maxdiff(T_after, T_before), sigdigits = 4),
            " K   (expect a few K for fac_add = 2)")

    println("\n    clock still ", p2.clock.time, "   ",
            p2.clock.time == ref.prognostic.clock.time ? "ok" : "DIFFERS")












    return nothing
end





