### Timing evaluation
###
### Summarizes the raw samples of generate_timing
###         - 1) Timing table
###         - 2) Print
###
### Timing modes:
###         - sweep:                one full global loop of parameterization! 
###         - step:                 one full SpeedyWeather.timestep                  
###
### Columns (every time is the median over the samples):
###         - sweep_ratio:          sweep time relative to the reference (first unit): emulator / reference
###         - sweep_ratio_lo/hi:    25 % / 75 % quantile of the per-round ratios (spread of the ratio)
###         - sweep_ms:             median sweep time in ms
###         - step_ms:              median full timestep in ms
###         - lw_share:             sweep / step, the share of a timestep spent in longwave radiation
###         - noise:                median / minimum of the sweep, >> 1 means the machine was busy -> rerun
###         - kb:                   allocated KB per sweep (should be 0)










### 1) Timing table

# Process pre-generated timing data into a table
function timing_table(timing; reference = first(keys(timing.units)))

    # Define reference and define table
    ref = timing.units[reference].sweep_ms
    table = DataFrame()

    # Loop over all units
    for (unit, u) in pairs(timing.units)

        # Extract sweep and step times
        sweep = u.sweep_ms
        step  = u.step_ms

        # Calculate ratio for all rounds
        ratios = sweep ./ ref

        # Push values onto the table
        push!(table, (;
            unit           = string(unit),
            sweep_ratio    = median(ratios),
            sweep_ratio_lo = quantile(ratios, 0.25),
            sweep_ratio_hi = quantile(ratios, 0.75),
            sweep_ms       = median(sweep),
            step_ms        = median(step),
            lw_share       = median(sweep) / median(step),
            noise          = median(sweep) / minimum(sweep),
            kb             = u.sweep_bytes / 1024,
        ))
    end

    return table
end










### 2) Print

# Print the timing table together with the machine it was measured on
function print_timing(timing; reference = first(keys(timing.units)))

    # Create data table and extract machine info
    table = timing_table(timing; reference)
    m = timing.machine

    
    # Print machine data the numbers were produced on
    println("$(m.host) | $(m.cpu) | julia threads $(m.julia_threads) | BLAS threads $(m.blas_threads) | " *
            "job $(m.slurm_job) | $(timing.npoints) columns")
    println()

    # Print Header
    println(rpad("unit", 22), lpad("sweep/ref", 11), lpad("IQR", 15), lpad("sweep ms", 11),
            lpad("step ms", 10), lpad("LW share", 10), lpad("noise", 8), lpad("KB", 8))
    println("-"^95)

    # One row per unit
    for row in eachrow(table)
        iqr = "$(round(row.sweep_ratio_lo, digits = 2))-$(round(row.sweep_ratio_hi, digits = 2))"
        println(rpad(String(row.unit), 22),
                lpad(string(round(row.sweep_ratio, digits = 2), "×"), 11),
                lpad(iqr, 15),
                lpad(round(row.sweep_ms, digits = 3), 11),
                lpad(round(row.step_ms, digits = 2), 10),
                lpad(string(round(100 * row.lw_share, digits = 1), " %"), 10),
                lpad(round(row.noise, digits = 2), 8),
                lpad(round(row.kb, digits = 1), 8))
    end

    # Warn if the machine was busy
    worst = maximum(table.noise)
    worst > 1.1 && @warn "Machine was not quiet (median/min up to $(round(worst, digits = 2))) - rerun?!"

    return nothing
end
