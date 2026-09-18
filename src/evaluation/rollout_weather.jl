### Weather Evaluation
###
### Evaluations of pre-generated 14-day rollouts (generate_rollout)
###         - 1) Helpers
###         - 2) Processing
###         - 3) Skill
###         - 4) Plotting
###
### Possible metrics include:
###         - :rmse:    root mean square error
###         - :bias:    mean error
###         - :maxdiff: maximum absolute error
### The specific calculation and use of metric is explained in the corresponding processing function,
###     metric is applied WITHIN a trajectory, then averages across trajectories. 
###
### Rollout forms: rollout.___
###         - scores:       (lead_time, layer, traj)
###         - field_xxx:    (window, gridpoint, layer, traj)
###
### Possible evaluations include:
###         - Weather growth:           metric vs. lead time
###         - Vertical profiles:        layers vs. metric (heatmap)
###         - Zonal cross section:      layer vs. ring (heatmap)










### 1) Helpers

# Reduction of the values of ONE trajectory (e.g. over layers or ring points) according to a weather metric
#   - a non-finite value means the trajectory blew up, so the whole trajectory becomes NaN
function reduce_metric(values, metric)

    # Check if all elements are finite
    all(isfinite, values) || return NaN

    # Calculate return according to given metric
    metric === :rmse    && return sqrt(Float64(mean(abs2, values)))     # root mean square error
    metric === :bias    && return Float64(mean(values))                 # mean error
    metric === :maxdiff && return Float64(maximum(abs, values))         # maximum absolute error

    # Throw error if metric is unknown
    error("unknown metric $(metric) - use :rmse, :bias or :maxdiff")
end










### 2) Processing

# Returns rollout statistics (mean, std, rms, n_valid) of a specific probe and metric
#   Order:  - 1) within a trajectory: the metric over all grid points and layers
#           - 2) across trajectories: mean (the curve) and std (the band)
function weather_growth(rollout, probe, metric)

    # Score of a specific probe and metric in form (lead_time, layer, traj)
    scores = rollout.scores[probe][metric]

    # Reduces scores along layer dimension to form (lead_time, traj)
    traj_scores = [reduce_metric(view(scores, lead, :, traj), metric)
                   for lead in axes(scores, 1), traj in axes(scores, 3)]

    # Calculate and return trajectory statistics (lead_time, )
    return (; days = rollout.days, traj_stats(traj_scores)...)
end


# Metric per layer at a given lead day, statistics over trajectories
#   Order:  - 1) within a trajectory: the metric over all grid points, layers not reduced
#           - 2) across trajectories: mean (the curve) and std (error bars)
function weather_profile(rollout, probe, day, metric)

    # Score of a specific probe and metric in form (lead_time, layer, traj)
    scores = rollout.scores[probe][metric]

    # Choose a specific lead day to obtain (layer, traj)
    layer_scores = scores[day_index(rollout.days, day), :, :]

    # Compute and return trajectory statistics (layer, )
    return (; layers = collect(axes(scores, 2)), traj_stats(layer_scores)...)
end


# Zonal cross section of a metric at a given lead day in form of (ring, layer)
#   Order:  - 1) within a trajectory: the metric over all grid points of a ring, layers not reduced
#           - 2) across trajectories: mean
function weather_zonal(rollout, probe, day, metric)

    # Extract grid and calculate index for specific lead day
    grid = rollout.spectral_grid.grid
    i_day = day_index(rollout.field_days, day)

    # Calculate errors (between run and reference) for lead day in form (npoints, layer, traj)
    errors = rollout.field_run[probe][i_day, :, :, :] .- rollout.field_ref[probe][i_day, :, :, :]

    # Reduce scores along grid dimension (group into rings and apply metric there) to obtain (ring, layer, traj)
    #   - eachring(grid) returns e.g. 1:20, 21:44, ... for every ring
    zonal_scores = [reduce_metric(view(errors, ring, k, traj), metric)
                   for ring in eachring(grid), k in axes(errors, 2), traj in axes(errors, 3)]


    # Calculate trajectory statistics (ring, layer)
    zonal = zeros(size(zonal_scores, 1), size(zonal_scores, 2))
    for k in axes(zonal_scores, 2)
        zonal[:, k] = traj_stats(view(zonal_scores, :, k, :)).mean
    end

    return zonal
end










### 3) Skill

# Skill evaluation of the weather leg: RMSE of one probe at one lead day
#   Order:  - 1) within a trajectory: RMSE over all grid points and layers at a given day
#           - 2) across trajectories: mean and std, n_valid says how many trajectories were still alive
function weather_skill(rollout; probe = :T, day = 14)

    # RMSE curve of the probe and index of the lead day
    growth = weather_growth(rollout, probe, :rmse)
    i_day  = day_index(growth.days, day)

    # Return mean, std and number of alive trajectories at the lead day
    return (; rmse = growth.mean[i_day], std = growth.std[i_day], n_valid = growth.n_valid[i_day])
end










### 4) Plotting

# One metric against lead time, one panel per probe, one line per rollout
function plot_weather_growth(
    rollouts,                       # weather rollouts, keyed by unit
    metric;                         # :rmse, :bias or :maxdiff
    probes = (:T, :olw, :slwd),     # one panel each
    caps   = nothing,               # rmse_caps result, drawn dashed
    looks  = nothing,               # appearance per unit
    title  = "",                    # figure title
    style  = (;),                   # entries of growth_style() to change
)

    # Full style and figure
    style     = checked_merge(growth_style(), style)
    n_panels  = length(probes)
    n_entries = n_legend_entries(looks, keys(rollouts))
    fig       = new_figure(style, n_panels; title, n_entries)


    # One panel per probe
    panel_ax = map(enumerate(probes)) do (i_panel, probe)

        # Define panel
        ax = panel(fig, style, i_panel, n_panels; xlabel = "lead time [days]", ylabel = axis_label(metric, probe))

        # A signed metric gets a zero line
        metric === :bias && hlines!(ax, [0]; color = :gray, linestyle = :dash, linewidth = style.linewidth / 2)

        # One line per rollout
        for (i_unit, (unit, rollout)) in enumerate(pairs(rollouts))
            draw_curve!(ax, weather_growth(rollout, probe, metric), look_of(looks, unit, i_unit, style), style;
                        n_traj = length(rollout.traj_ic))
        end

        # RMSE cap last, so the cap sits on top
        if metric === :rmse && !isnothing(caps) && haskey(caps, probe)
            hlines!(ax, [caps[probe].mean]; color = :gray40, linestyle = :dash, linewidth = style.linewidth)
        end

        return ax
    end

    # Add legend and title to the figure
    add_legend!(fig, first(panel_ax), style, n_panels, n_entries)
    add_title!(fig, style, title)

    return fig
end



# Vertical profile at a given lead day, one panel per metric, one line per rollout
function plot_weather_profile(
    rollouts,                               # weather rollouts, keyed by unit
    probe,                                  # probe (a profile, e.g. :T)
    day;                                    # lead day
    metrics = (:rmse, :bias, :maxdiff),     # one panel each
    looks   = nothing,                      # appearance per unit
    title   = "",                           # figure title
    style   = (;),                          # entries of profile_style() to change
)

    # Full style and figure
    style     = checked_merge(profile_style(), style)
    n_panels  = length(metrics)
    n_entries = n_legend_entries(looks, keys(rollouts))
    fig       = new_figure(style, n_panels; title, n_entries)


    # Layer axis of the probe, shared by all rollouts
    layers = collect(axes(first(values(rollouts)).scores[probe].rmse, 2))

    # One panel per metric, layer 1 (top of the atmosphere) at the top
    panel_ax = map(enumerate(metrics)) do (i_panel, metric)

        # Define panel
        ax = panel(fig, style, i_panel, n_panels; xlabel = axis_label(metric, probe), ylabel = "layer",
                   yticks = layers, yreversed = true)

        # A signed metric gets a zero line
        metric === :bias && vlines!(ax, [0]; color = :gray, linestyle = :dash, linewidth = style.linewidth / 2)

        # One line per rollout
        for (i_unit, (unit, rollout)) in enumerate(pairs(rollouts))

            # Merge looks and extract profile of current loop rollout
            look = look_of(looks, unit, i_unit, style)
            profile = weather_profile(rollout, probe, day, metric)

            # Draw errorbars and connected layer points
            style.band && errorbars!(ax, profile.mean, profile.layers, profile.std; direction = :x, color = look.color)
            scatterlines!(ax, profile.mean, profile.layers; color = look.color, linestyle = look.linestyle,
                          linewidth = style.linewidth, marker = look.marker, markersize = look.markersize,
                          label = look.label)
        end

        return ax
    end

    # Add legend and title to the figure
    add_legend!(fig, first(panel_ax), style, n_panels, n_entries)
    add_title!(fig, style, title)

    return fig
end



# Zonal cross section (latitude x layer) of one metric at a given lead day, one panel per rollout
function plot_weather_zonal(
    rollouts,                   # weather rollouts, keyed by unit
    probe,                      # probe (a profile, e.g. :T)
    day,                        # lead day (one of the stored field days)
    metric;                     # :rmse, :bias or :maxdiff
    looks  = nothing,          # labels per unit (panel titles)
    title  = "",                # figure title
    style  = (;),               # entries of zonal_style() to change
)

    # Compute sections for each rollout and extract latitude of rings
    sections = [weather_zonal(rollout, probe, day, metric) for rollout in values(rollouts)]
    latd     = RingGrids.get_latd(first(values(rollouts)).spectral_grid.grid)

    # Plot heatmaps
    return plot_zonal(sections, latd; titles = unit_names(looks, keys(rollouts)),
                      signed = metric === :bias, label = axis_label(metric, probe), title, style)
end
