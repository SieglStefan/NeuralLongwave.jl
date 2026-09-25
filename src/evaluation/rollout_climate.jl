### Climate Evaluation
###
### Evaluations of pre-generated multi-year climate rollouts (generate_rollout)
###         - 1) Helpers
###         - 2) Processing
###         - 3) Statistics and climate check
###         - 4) Plotting
###
### Rollout forms: rollout.___
###         - global_mean:  (sample, layer, traj)
###         - year_mean:    (year, gridpoint, layer, traj)
###
### Possible evaluations include:
###         - Climate check table:      pass/fail of every unit against the noise floor (t-test, zonal_rmse)
###         - Climate drift:            global bias vs. time
###         - Zonal cross sections:     layer vs. ring (heatmap), bias or t-value
###         - Lon-Lat maps:             lon. vs. lat. (heatmap), bias or t-value (noisier, appendix)










### 1) Helpers

# Check that a rollout and its reference are comparable: same start states and same sampling
function check_climate_pair(rollout, ref)

    # Settings that have to agree, with their values in the rollout and the reference
    checks = (;
        restart_scheme   = (rollout.restart_scheme, ref.restart_scheme),        # same restart state scheme folder
        restart_unit     = (rollout.restart_unit, ref.restart_unit),            # same restart state unit
        traj_ic          = (rollout.traj_ic, ref.traj_ic),                      # same restart state IC
        traj_j           = (rollout.traj_j, ref.traj_j),                        # same restart state within a IC
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


# Reduce trajectory statistics to one value per row according to a climate metric
#   - stats comes from traj_stats() and is a NamedTuple of form (row, ), e.g. row = time, layer or ring
#   - bias:     Extract the mean bias per row
#   - t:        Extract the mean bias in units of its standard error per row
function climate_metric(stats, metric)

    # Define metric
    metric === :bias && return stats.mean
    metric === :t    && return stats.mean ./ (stats.std ./ sqrt.(stats.n_valid))

    error("unknown metric $(metric) - use :bias or :t")
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
    window > 1 || return (; days, traj_stats(column_bias)...)


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


# Lon-lat map of a specific probe and one metric (:bias or :t) of given years: one value per grid point
function climate_lonlat(rollout, ref, probe; metric = :bias, years = 2:3)

    # Calculate bias of given years to obtain (gridpoint, layer, traj)
    traj_bias = bias_years(rollout, ref, probe, years)

    # Calculate mean across layers and drop the layer dimension: (gridpoint, traj)
    column_bias = dropdims(mean(traj_bias; dims = 2); dims = 2)

    # Calculate trajectory statistics and reduce them to the metric (gridpoint, )
    return climate_metric(traj_stats(column_bias), metric)
end


# Zonal cross section of a metric (:bias or :t) of given years in form of (ring, layer)
#   - the ring mean is taken per trajectory FIRST, so the t-value measures the disagreement between
#     trajectories, not the scatter along the ring
function climate_zonal(rollout, ref, probe; metric = :bias, years = 2:3)

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
        zonal[:, k] = climate_metric(traj_stats(view(zonal_bias, :, k, :)), metric)
    end

    return zonal
end










### 3) Statistics and climate check

# Two-sided 95 % quantile of Student's t distribution for df degrees of freedom 
#   - 95% of the area lies between -t_crit and + t_crit (2.5% in each tail)
#   - normal distribution: t_crit = 1.96 (≈ 2 SE)
#   - Student's t: the std is estimated from few samples, so the tails are wider (df = 11: t_crit ≈ 2.2)
#   - a mean further than t_crit * SE from 0 is not explained by chance
t_quantile(df) = df < 1 ? NaN : Distributions.quantile(Distributions.TDist(df), 0.975)



# Climate statistics of the bias (unit - reference), over the trajectories (= restarts)
#   - per trajectory i: d_i = area-weighted mean of (unit - reference) over grid points and layers
#   - bias, std, se:    mean, standard deviation and standard error (std / sqrt(n)) of the d_i
#   - zonal_rmse:       the global bias field averaged over trajectories FIRST, then zonally averaged per
#                           (ring, layer), then its area-weighted RMS (leads to a number)
#   - n_valid, n_traj:  trajectories that completed the years / all trajectories
function climate_stats(rollout, ref; probe = :T, years = 2:3)

    # Calculate bias of given years to obtain (gridpoint, layer, traj) and extract area weights
    traj_bias = bias_years(rollout, ref, probe, years)
    w = area_weights(rollout.spectral_grid)


    # Per trajectory, as a one-row matrix (1, traj): the global signed bias d_i
    #   - (1,12) form for traj_stats()
    global_bias = [wmean(view(traj_bias, :, :, traj), w) for _ in 1:1, traj in axes(traj_bias, 3)]

    # Statistics over trajectories
    stats = traj_stats(global_bias)


    # Trajectories that completed the years
    alive = [all(isfinite, view(traj_bias, :, :, traj)) for traj in axes(traj_bias, 3)]

    # Ensemble-mean bias field over the alive trajectories (gridpoint, layer)
    mean_bias = dropdims(mean(view(traj_bias, :, :, alive); dims = 3); dims = 3)

    # Extract ring indices and ring weights
    rings = eachring(rollout.spectral_grid.grid)
    ring_weight = [sum(view(w, ring)) for ring in rings]

    # Zonal mean of that field per (ring, layer), rings weighted by their area
    zonal_mse   = 0.0
    for (j, ring) in enumerate(rings), k in axes(mean_bias, 2)
        zonal_mse += ring_weight[j] * mean(view(mean_bias, ring, k))^2
    end
    zonal_rmse = sqrt(zonal_mse / (sum(ring_weight) * size(mean_bias, 2)))


    # Return stats
    return (; bias       = stats.mean[1],
              std        = stats.std[1],
              se         = stats.std[1] / sqrt(stats.n_valid[1]),
              zonal_rmse = zonal_rmse,
              n_valid    = stats.n_valid[1],
              n_traj     = length(alive))
end


# Climate check: is every unit within the internal variability of the reference?
#   - noise floor (0_OBLW_pert against 0_OBLW) is the first row, it shows what chance alone produces
#   - ci_lo_T / ci_hi_T: 95 % confidence interval of the true T bias (bias ± t_quantile(n-1) * se)
#   - a unit passes if
#       - all its trajectories survived the years
#       - |bias| of T and of the TOA imbalance < t_quantile(n-1) * SE (t-test: not distinguishable from 0)
#       - zonal_rmse of T <= zonal_tol * the floor's (the floor is one realization, hence a margin)
function climate_table(
    ro_climate,             # climate rollouts, keyed by unit
    ref,                    # reference climate rollout (climate_noise 0_OBLW)
    floor;                  # noise-floor climate rollout (climate_noise 0_OBLW_pert)
    years = 2:3,            # evaluated years (nothing = all but the first)
    zonal_tol = 1.5,        # allowed zonal_rmse relative to the floor
)

    # Zonal RMSE of the floor, the yardstick of every unit
    floor_zonal = climate_stats(floor, ref; probe = :T, years).zonal_rmse

    
    # One row per rollout, the floor first
    rollouts = merge((; var"0_OBLW_pert (floor)" = floor), ro_climate)
    rows = map(collect(keys(rollouts))) do unit

        # Statistics of temperature and TOA energy imbalance
        T   = climate_stats(rollouts[unit], ref; probe = :T, years)
        imb = climate_stats(rollouts[unit], ref; probe = :imb_TOA, years)

        # The four criteria
        t_crit      = t_quantile(T.n_valid - 1)             # critical t-value (e.g. 2.2)
        pass_alive  = T.n_valid == T.n_traj                 # all trajectories survived
        pass_T      = abs(T.bias) <= t_crit * T.se          # if the T bias is within the critical range
        pass_imb    = abs(imb.bias) <= t_crit * imb.se      # if the TOA imbalance bias is within the critical range
        zonal_ratio = T.zonal_rmse / floor_zonal            # ratio of unit's zonal RMSE to the floor's
        pass_zonal  = zonal_ratio <= zonal_tol              # if the zonal RMSE is within the allowed tolerance

        # Return table entries
        return (; unit        = string(unit),                       # name of unit
                  alive       = "$(T.n_valid)/$(T.n_traj)",         # fraction of survived units

                  bias_T      = T.bias,                             # temperature bias
                  se_T        = T.se,                               # temperature standard error
                  t_T         = T.bias / T.se,                      # temperature t-value of bias (units of SE away from 0)
                  ci_lo_T     = T.bias - t_crit * T.se,             # lower bound allowed range
                  ci_hi_T     = T.bias + t_crit * T.se,             # upper bound allowed range
                
                  bias_imb    = imb.bias,                           # TOA imbalance bias
                  se_imb      = imb.se,                             # TOA imbalance standard error
                  t_imb       = imb.bias / imb.se,                  # TOA imbalance t-value of bias

                  t_crit      = t_crit,                             # critical SE (e.g. 2.2)
                  zonal_rmse  = T.zonal_rmse,                       # RMSE over all rings
                  zonal_ratio = zonal_ratio,                        # unit / floor
                  pass        = pass_alive && pass_T && pass_imb && pass_zonal)     # all criteria passed
    end

    return DataFrame(rows)
end










### 4) Plotting

# Climate drift (bias=unit-reference) against time, one panel per probe, one line per rollout
function plot_climate_drift(
    rollouts,                                   # climate rollouts, keyed by unit
    ref,                                        # reference climate rollout (0_OBLW)
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
                        n_traj = length(rollout.traj_ic))
        end

        return ax
    end

    # Add legend and title to the figure
    add_legend!(fig, first(panel_ax), style, n_panels, n_entries)
    add_title!(fig, style, title)

    return fig
end



# Heatmap settings of a climate metric
#   - :bias:    color range from the data, label in physical units
#   - :t:       fixed color range +-t_range, cells beyond the t-quantile highlighted
function climate_heatmap(metric, probe, rollouts, style)

    # Bias: nothing to fix
    metric === :bias && return (; label = axis_label(:bias, probe), colorrange = nothing, highlight = nothing)

    # t-value: threshold of the t-test from the number of trajectories
    t_crit = t_quantile(length(first(values(rollouts)).traj_j) - 1)
    return (; label      = "t = bias / SE of $(probe_label(probe))  (magenta: |t| > $(round(t_crit, digits = 2)))",
              colorrange = (-style.t_range, style.t_range),
              highlight  = t_crit)
end


# Lon-lat maps of the bias or t-value of given years, one panel per rollout
function plot_climate_lonlat(
    rollouts,               # climate rollouts, keyed by unit
    ref,                    # reference climate rollout (0_OBLW)
    probe;                  # probe
    metric = :bias,         # :bias (mean over trajectories) or :t (bias / standard error)
    years  = 2:3,           # averaged years (e.g. 3 or 2:10, nothing = all but the first)
    looks  = nothing,       # labels per unit (panel titles)
    title  = "",            # figure title
    style  = (;),           # entries of lonlat_style() to change
)

    # Collect lonlat maps for each rollout
    maps = [climate_lonlat(rollout, ref, probe; metric, years) for rollout in values(rollouts)]

    # Label, color range and highlighted cells of the metric
    heat = climate_heatmap(metric, probe, rollouts, checked_merge(lonlat_style(), style))

    # Create lonlat heatmap plots
    return plot_lonlat(maps, first(values(rollouts)).spectral_grid.grid; titles = unit_names(looks, keys(rollouts)),
                       signed = true, heat..., title, style)
end



# Zonal cross section (latitude x layer) of the bias or t-value of given years, one panel per rollout
function plot_climate_zonal(
    rollouts,               # climate rollouts, keyed by unit
    ref,                    # reference climate rollout (0_OBLW)
    probe;                  # probe (a profile, e.g. :T)
    metric = :bias,         # :bias (mean over trajectories) or :t (bias / standard error)
    years  = 2:3,           # averaged years (e.g. 3 or 2:10, nothing = all but the first)
    looks  = nothing,       # labels per unit (panel titles)
    title  = "",            # figure title
    style  = (;),           # entries of zonal_style() to change
)

    # Compute sections for each rollout and extract latitude of rings
    sections = [climate_zonal(rollout, ref, probe; metric, years) for rollout in values(rollouts)]
    latd     = RingGrids.get_latd(first(values(rollouts)).spectral_grid.grid)

    # Label, color range and highlighted cells of the metric
    heat = climate_heatmap(metric, probe, rollouts, checked_merge(zonal_style(), style))

    # Plot heatmaps
    return plot_zonal(sections, latd; titles = unit_names(looks, keys(rollouts)),
                      signed = true, heat..., title, style)
end
