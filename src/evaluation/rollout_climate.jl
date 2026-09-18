### Climate Evaluation
###
### Evaluations of pre-generated 3-year rollouts (generate_rollout)
###         - 1) Helpers
###         - 2) Processing
###         - 3) Skill
###         - 4) Plotting
###
### Possible metrics include:
###         - :bias: mean over traj. (warming or cooling)
###         - :rmsb: rms over traj. (bias size)
### Other dimensions (like time or space) are just averaged (bias) BEFORE trajectory statistics,
### where metric is applied
###
### Rollout forms: rollout.___
###         - global_mean_xxx:  (lead_time, layer, traj)
###         - time_mean_xxx:    (window, gridpoint, layer, traj)
###
### Possible evaluations include:
###         - Climate drift:            metric vs. lead time
###         - Lon-Lat maps:             lon. vs. lat. (heatmap)
###         - Zonal cross sections:     layer vs. ring (heatmap)










### 1) Helpers

# Calculate bias (run - reference) for one year of a specific probe
#   - the climate leg stores one time-mean map per year (climate_n_windows = 3), so a year is a window index
function year_bias(rollout, probe, year)

    # Check if rollout window is approx. one year long
    rollout.window_samples * rollout.gap_days ≈ 366 ||
        error("Climate rollout does not store one window per year - set climate_n_windows to the number of years")

    # Calculate bias between run and reference to obtain (gridpoint, layer, traj)
    return rollout.time_mean_run[probe][year, :, :, :] .- rollout.time_mean_ref[probe][year, :, :, :]
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



# Translate a climate metric into a traj_stats statistic
function translate_metric(metric)
    
    # Possible metrics
    metric === :bias && return :mean
    metric === :rmsb && return :rms 

    # Throw error if metric is unknown
    error("Unknown climate metric $(metric) - use :bias or :rmsb")
end










### 2) Processing

# Returns climate bias statistics (mean, std, rms, n_valid) of a specific probe
function climate_drift(rollout, probe)

    # Calculate mean between run and reference and average over layers to obtain (sample, traj)
    column_bias = dropdims(mean(rollout.global_mean_run[probe] .- rollout.global_mean_ref[probe]; dims = 2); dims = 2)

    # Compute and return trajectory statistics (lead_time, )
    return (; days = rollout.days, traj_stats(column_bias)...)
end


# Lon-lat map of a specific probe and one metric of a given year: one value per grid point
function climate_lonlat(rollout, probe, metric; year = 3)

    # Calculate bias of given year to obtain (gridpoint, layer, traj)
    traj_bias = year_bias(rollout, probe, year)

    # Calculate mean across layers and drop the layer dimension: (gridpoint, traj)
    column_bias = dropdims(mean(traj_bias; dims = 2); dims = 2)

    # Calculate and return trajectory statistics (gridpoint, )
    return traj_stats(column_bias)[translate_metric(metric)]
end


# Zonal cross section of a metric of a given year year in form of (ring, layer)
function climate_zonal(rollout, probe, metric; year = 3)

    # Calculate bias of given year to obtain (gridpoint, layer, traj) and extract grid
    traj_bias = year_bias(rollout, probe, year)
    grid = rollout.spectral_grid.grid

    # Calculate mean along grid dimension (group into rings and apply metric there) to obtain (ring, layer, traj)
    #   - eachring(grid) returns e.g. 1:20, 21:44, ... for every ring
    zonal_bias = [mean(view(traj_bias, ring, k, traj))
                  for ring in eachring(grid), k in axes(traj_bias, 2), traj in axes(traj_bias, 3)]

                  
    # Calculate trajectory statistics (ring, layer)
    zonal = zeros(size(zonal_bias, 1), size(zonal_bias, 2))
    for k in axes(zonal_bias, 2)
        zonal[:, k] = traj_stats(view(zonal_bias, :, k, :))[translate_metric(metric)]
    end

    return zonal
end










### 3) Skill

# Skill evaluation of the climate leg: bias and RMSB of the global, year-mean bias of one probe
#   Order:  - 1) within a trajectory: area-weighted mean over all grid points and layers of the year-mean bias
#           - 2) across trajectories: bias = mean, std, rmsb = rms, n_valid says how many trajectories completed the year
function climate_skill(rollout; probe = :T, year = 3)

    # Calculate bias of given year to obtain (gridpoint, layer, traj) and the area weights of the grid
    traj_bias = year_bias(rollout, probe, year)
    w = area_weights(rollout.spectral_grid)

    # Global mean of every trajectory as a one-row matrix (1, traj), NaN if the trajectory did not complete the year
    global_bias = [wmean(view(traj_bias, :, :, traj), w) for _ in 1:1, traj in axes(traj_bias, 3)]

    # Statistics over trajectories
    stats = traj_stats(global_bias)

    return (; bias = stats.mean[1], std = stats.std[1], rmsb = stats.rms[1], n_valid = stats.n_valid[1])
end










### 4) Plotting

# Drift of one climate metric against lead time, one panel per probe, one line per rollout
function plot_climate_drift(
    rollouts,                                   # climate rollouts, keyed by unit
    metric;                                     # :bias or :rmsb
    probes = (:T, :olw, :slwd, :imb_TOA),       # one panel each
    days   = nothing,                           # shown days, e.g. (732, 1098) (nothing = the whole run)
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
        ax = panel(fig, style, i_panel, n_panels; xlabel = "lead time [days]", ylabel = axis_label(metric, probe))

        # A signed metric gets a zero line
        metric === :bias && hlines!(ax, [0]; color = :gray, linestyle = :dash, linewidth = style.linewidth / 2)

        # One line per rollout: the mean over trajectories for :bias, the rms for :rmsb
        for (i_unit, (unit, rollout)) in enumerate(pairs(rollouts))
            curve = crop(climate_drift(rollout, probe), days)
            draw_curve!(ax, curve, look_of(looks, unit, i_unit, style), style;
                        value = translate_metric(metric), n_traj = length(rollout.traj_ic))
        end

        return ax
    end

    # Add legend and title to the figure
    add_legend!(fig, first(panel_ax), style, n_panels, n_entries)
    add_title!(fig, style, title)

    return fig
end



# Lon-lat maps of one climate metric of one year, one panel per rollout
function plot_climate_lonlat(
    rollouts,               # climate rollouts, keyed by unit
    probe,                  # probe
    metric;                 # :bias or :rmsb
    year   = 3,             # averaged year (1, 2 or 3)
    looks  = nothing,       # labels per unit (panel titles)
    title  = "",            # figure title
    style  = (;),           # entries of lonlat_style() to change
)

    # Collect lonlat maps for each rollout
    maps = [climate_lonlat(rollout, probe, metric; year) for rollout in values(rollouts)]

    # Create lonlat heatmap plots
    return plot_lonlat(maps, first(values(rollouts)).spectral_grid.grid; titles = unit_names(looks, keys(rollouts)),
                       signed = metric === :bias, label = axis_label(metric, probe), title, style)
end



# Zonal cross section (latitude x layer) of one climate metric of one year, one panel per rollout
function plot_climate_zonal(
    rollouts,               # climate rollouts, keyed by unit
    probe,                  # probe (a profile, e.g. :T)
    metric;                 # :bias or :rmsb
    year   = 3,             # averaged year (1, 2 or 3)
    looks  = nothing,       # labels per unit (panel titles)
    title  = "",            # figure title
    style  = (;),           # entries of zonal_style() to change
)

    # Compute sections for each rollout and extract latitude of rings
    sections = [climate_zonal(rollout, probe, metric; year) for rollout in values(rollouts)]
    latd     = RingGrids.get_latd(first(values(rollouts)).spectral_grid.grid)

    # Plot heatmaps
    return plot_zonal(sections, latd; titles = unit_names(looks, keys(rollouts)),
                      signed = metric === :bias, label = axis_label(metric, probe), title, style)
end
