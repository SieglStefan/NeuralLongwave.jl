### Climate Evaluation
###
### Evaluations of pre-generated multi-year climate rollouts (generate_rollout)
###         - 1) Helpers
###         - 2) Processing
###         - 3) Statistics
###         - 4) Plotting
###
### Rollout forms: rollout.___
###         - global_mean:  (sample, layer, traj)
###         - year_mean:    (year, gridpoint, layer, traj)
###
### Possible evaluations include:
###         - Climate bias:             global bias ± 95 % CI against a tolerance band
###         - Climate drift:            global bias vs. time
###         - Zonal cross sections:     layer vs. ring (heatmap) of the bias










### 1) Helpers

# Check that a rollout and its reference are comparable: same start states and same sampling
function check_climate_pair(rollout, ref)

    # Settings that have to agree, with their values in the rollout and the reference
    checks = (;
        restart_scheme   = (rollout.restart_scheme, ref.restart_scheme),        # same restart state scheme folder
        restart_unit     = (rollout.restart_unit, ref.restart_unit),            # same restart state unit
        traj_run         = (rollout.traj_run, ref.traj_run),                    # same restart runs
        traj_season      = (rollout.traj_season, ref.traj_season),              # same restart seasons
        gap_days         = (rollout.gap_days, ref.gap_days),                    # same gap between samples
        samples_per_year = (rollout.samples_per_year, ref.samples_per_year),    # same total number of samples per year
    )

    # Throw an error naming every mismatching setting
    mismatch = [key for key in keys(checks) if checks[key][1] != checks[key][2]]
    isempty(mismatch) || error("Rollout and reference are not comparable - different settings: " *
                               join(["$(key) = $(checks[key][1]) vs. $(checks[key][2])" for key in mismatch], ", "))

    return nothing
end



# Calculate bias (unit - reference) of a specific probe, averaged over one or several years (e.g. 3 or 2:10)
function bias_years(rollout, ref, probe, years)

    # Check that both rollouts are comparable
    check_climate_pair(rollout, ref)

    # Average the chosen years (vcat turns 3 into [3]) to obtain (gridpoint, layer, traj)
    run = dropdims(mean(rollout.year_mean[probe][vcat(years), :, :, :]; dims = 1); dims = 1)
    reference = dropdims(mean(ref.year_mean[probe][vcat(years), :, :, :]; dims = 1); dims = 1)

    return run .- reference
end



# Part of a curve between two days (days = nothing: keeps the whole curve)
#   - curve is of shape (; days = [...], mean = [...], std = [...], rms = [...], n_valid = [...])
#   - days = (start, end)
function crop(curve, days)

    # Keep the whole curve
    isnothing(days) && return curve

    # Calculate indices of to be kept curve
    keep = (curve.days .>= days[1]) .& (curve.days .<= days[2])

    # Crop curve to obtain e.g. (; days = [4,5,6], mean = [mean[4], ...], ...)
    return map(entry -> entry[keep], curve)
end










### 2) Processing

# Returns climate bias statistics (mean, std, min, max, rms, n_valid) of a specific probe
#   - every trajectory is smoothed FIRST, then the statistics are taken across trajectories
function climate_drift(rollout, ref, probe; smooth_days = 366)

    # Check that both rollouts are comparable
    check_climate_pair(rollout, ref)

    # Samples both rollouts have (the shorter rollout sets the length)
    n_samples = min(length(rollout.days), length(ref.days))
    days = rollout.days[1:n_samples]

    # Calculate bias between unit and reference and average over layers to obtain (sample, traj)
    diff = rollout.global_mean[probe][1:n_samples, :, :] .- ref.global_mean[probe][1:n_samples, :, :]
    column_bias = dropdims(mean(diff; dims = 2); dims = 2)

    # Smoothing window in samples units
    window = round(Int, smooth_days / rollout.gap_days)


    # No smoothing requested: statistics of the raw bias
    window == 0 && return (; days, traj_stats(column_bias)...)


    # Smooth every trajectory separately with a running mean
    n_traj = size(column_bias, 2)
    smoothed = [running_mean(days, view(column_bias, :, traj), window) for traj in 1:n_traj]

    # Shortened day axis (the same for every trajectory) and smoothed bias in form (sample, traj)
    smoothed_days = first(smoothed[1])
    smoothed_bias = zeros(length(smoothed_days), n_traj)
    for traj in 1:n_traj
        smoothed_bias[:, traj] = last(smoothed[traj])
    end

    # Compute and return trajectory statistics of the smoothed biases (sample, )
    return (; days = smoothed_days, traj_stats(smoothed_bias)...)
end



# Zonal cross section of the bias of given years in form of (ring, layer)
#   - the ring mean is taken per trajectory FIRST, then the mean over trajectories
function climate_zonal(rollout, ref, probe; years = 2:3)

    # Calculate bias of given years to obtain (gridpoint, layer, traj) and extract grid
    traj_bias = bias_years(rollout, ref, probe, years)
    grid = rollout.spectral_grid.grid

    # Calculate mean along grid dimension (group into rings) to obtain (ring, layer, traj)
    #   - eachring(grid) returns e.g. 1:20, 21:44, ... for every ring
    zonal_bias = [mean(view(traj_bias, ring, k, traj))
                  for ring in eachring(grid), k in axes(traj_bias, 2), traj in axes(traj_bias, 3)]


    # Calculate trajectory statistics per layer and reduce them to the metric (ring, layer)
    zonal = zeros(size(zonal_bias, 1), size(zonal_bias, 2))
    for k in axes(zonal_bias, 2)
        zonal[:, k] = traj_stats(view(zonal_bias, :, k, :)).mean
    end

    return zonal
end










### 3) Statistics

# Two-sided 95 % quantile of Student's t distribution for df degrees of freedom 
#   - 95% of the area lies between -t_crit and + t_crit (2.5% in each tail)
#   - normal distribution: t_crit = 1.96 (≈ 2 SE)
#   - Student's t: the std is estimated from few samples, so the tails are wider (df = 11: t_crit ≈ 2.2)
#   - a mean further than t_crit * SE from 0 is not explained by chance
t_quantile(df) = df < 1 ? NaN : Distributions.quantile(Distributions.TDist(df), 0.975)



# Climate statistics of the bias (unit - reference), over the trajectories (= restarts)
#   - per trajectory i:     d_i = area-weighted mean of (unit - reference) over grid points and layers
#   - bias, std, se:        mean, standard deviation and standard error (std / sqrt(n)) of the d_i
#   - n_valid, n_traj:      trajectories that completed the years / all trajectories
function climate_stats(rollout, ref; probe = :T, years = 2:3)

    # Calculate bias of given years to obtain (gridpoint, layer, traj) and extract area weights
    traj_bias = bias_years(rollout, ref, probe, years)
    w = area_weights(rollout.spectral_grid)


    # Per trajectory, as a one-row matrix (1, traj): the global signed bias d_i
    #   - (1,12) form for traj_stats()
    global_bias = [wmean(view(traj_bias, :, :, traj), w) for _ in 1:1, traj in axes(traj_bias, 3)]

    # Statistics over trajectories
    stats = traj_stats(global_bias)


    return (; bias    = stats.mean[1],
              std     = stats.std[1],
              se      = stats.std[1] / sqrt(stats.n_valid[1]),
              n_valid = stats.n_valid[1],
              n_traj  = size(traj_bias, 3))
end










### 4) Plotting

# Climate drift (bias=unit-reference) against time, one panel per probe, one line per rollout
function plot_climate_drift(
    rollouts,                                   # climate rollouts, keyed by unit
    ref,                                        # reference climate rollout (OBLW/climate_ref)
    probes = (:T, :imb_TOA, :olw, :slwd);       # one panel each
    days   = nothing,                           # shown days, e.g. (732, 1098) (nothing = the whole run)
    smooth_days = 366,                          # temporal smoothing window in days
    looks  = nothing,                           # appearance per unit
    title  = "",                                # figure title
    style  = (;),                               # entries of drift_style() to change
)

    # Full style and figure
    style     = checked_merge(drift_style(), style)
    n_panels  = length(probes)
    n_entries = n_legend_entries(looks, keys(rollouts))
    fig       = new_figure(style, n_panels; title, n_entries)


    # One panel per probe
    panel_ax = map(enumerate(probes)) do (i_panel, probe)

        # Define panel
        ax = panel(fig, style, i_panel, n_panels; xlabel = "time [days]", ylabel = axis_label(:bias, probe))

        # One line per rollout: the bias averaged over trajectories, smoothed by a running mean
        for (i_unit, (unit, rollout)) in enumerate(pairs(rollouts))
            curve = crop(climate_drift(rollout, ref, probe; smooth_days), days)
            draw_curve!(ax, curve, look_of(looks, unit, i_unit, style), style;
                        n_traj = length(rollout.traj_run))
        end

        return ax
    end

    # Add legend and title to the figure
    add_legend!(fig, first(panel_ax), style, n_panels, n_entries)
    add_title!(fig, style, title)

    return fig
end



# Zonal cross section (latitude x layer) of the bias of given years, one panel per rollout
function plot_climate_zonal(
    rollouts,               # climate rollouts, keyed by unit
    ref,                    # reference climate rollout (OBLW/climate_ref)
    probe;                  # probe (a profile, e.g. :T)
    years  = 2:3,           # averaged years (e.g. 3 or 2:10)
    looks  = nothing,       # labels per unit (panel titles)
    layout = nothing,       # panel layout, 0/1 matrix e.g. [0 1 0; 1 1 1; 1 1 1] (nothing = row by row)
    title  = "",            # figure title
    style  = (;),           # entries of zonal_style() to change
)

    # Compute sections for each rollout and extract latitude of rings
    sections = [climate_zonal(rollout, ref, probe; years) for rollout in values(rollouts)]
    latd     = RingGrids.get_latd(first(values(rollouts)).spectral_grid.grid)

    # Plot heatmaps
    return plot_zonal(sections, latd; titles = unit_names(looks, keys(rollouts)),
                      signed = true, label = axis_label(:bias, probe), title, layout, style)
end



# Climate bias (unit - reference) with its 95 % confidence interval, one panel per probe, one row per rollout
#   - dot: mean over trajectories of the global bias d_i, bar: ± t_quantile(n-1) * SE (the t-test turned around)
#   - shaded: tolerance band ±tol - a unit catches the climate if its bar lies inside the band
function plot_climate_bias(
    rollouts,                       # climate rollouts, keyed by unit (the floor first, e.g. merge((; floor), units))
    ref;                            # reference climate rollout (OBLW/climate_ref)
    probes = (:T, :imb_TOA),        # one panel each
    years  = 2:3,                   # evaluated years
    tol    = nothing,               # tolerance per probe, e.g. (; T = 0.2, imb_TOA = 0.5) (nothing = no band)
    looks  = nothing,               # appearance per unit
    title  = "",                    # figure title
    style  = (;),                   # entries of bias_style() to change
)

    # Full style and figure
    style    = checked_merge(bias_style(), style)
    n_panels = length(probes)
    fig      = new_figure(style, n_panels; title)

    # One row per rollout, the first one on top
    units = collect(keys(rollouts))
    rows  = collect(length(units):-1:1)


    # One panel per probe
    for (i_panel, probe) in enumerate(probes)

        # Define panel, unit names only on the first one
        ax = panel(fig, style, i_panel, n_panels; xlabel = axis_label(:bias, probe),
                   yticks = (rows, unit_names(looks, units)), yticklabelsvisible = i_panel == 1)
        ylims!(ax, 0.5, length(units) + 0.5)

        # Tolerance band and zero line
        !isnothing(tol) && haskey(tol, probe) && vspan!(ax, -tol[probe], tol[probe]; color = (:gray, 0.2))
        vlines!(ax, [0]; color = :gray, linestyle = :dash, linewidth = style.linewidth / 2)

        # One dot with its confidence interval per rollout
        for (i_unit, unit) in enumerate(units)
            s    = climate_stats(rollouts[unit], ref; probe, years)
            look = look_of(looks, unit, i_unit, style)
            half = t_quantile(s.n_valid - 1) * s.se

            errorbars!(ax, [s.bias], [rows[i_unit]], [half]; direction = :x, color = look.color,
                       linewidth = style.linewidth, whiskerwidth = 8)
            scatter!(ax, [s.bias], [rows[i_unit]]; color = look.color, marker = look.marker,
                     markersize = look.markersize)
        end
    end

    # Add title to the figure (units are on the y-axis, no legend)
    add_title!(fig, style, title)

    return fig
end