### Raw data evaluation
###
### Global means, RMSE distances between trajectories and error growth statistics
### of a raw dataset
###         - 1) Processing
###         - 2) Error growth
###         - 3) Plotting
###
### Possible evaluations include: (over all points and layers)
###         - Global means (metric = :mean)
###         - RMSE distances between trajectories (metric = :rmse)
###         - Error growth statistics (mean, std over trajectory pairs)









### 1) Processing

# Day of every stored state, and the distance between two states in days
function sample_axis(data)

    # Calculate gap between raw data points in days
    gap_days = data.gap_steps / data.steps_per_day

    # Caclulate range of samples in days (e.g. [7, 14, 21,...] for weekly)
    days = [i_state * gap_days for i_state in 0:data.n_states-1]

    return (; days, gap_days)
end


# Area weighted global mean of every probe at every stored state of one trajectory
#   - means[probe] is a timeseries one value per stored state
function global_means(raw_dir, traj; probes = keys(PROBES))

    with_raw_data(raw_dir, traj) do data

        # Area weights (npoints) and one container per probe
        aw = area_weights(data.spectral_grid)
        means = NamedTuple{Tuple(probes)}(Tuple(Float64[] for _ in probes))

        # States outer, probes inner - every data[i_state] reads a full state from disk
        for i_state in 0:data.n_states-1
            state = data[i_state]
            for probe in probes
                push!(means[probe], wmean(Array(PROBES[probe].func(state)), aw))
            end
        end

        return (; sample_axis(data)..., metric = :mean, means...)
    end
end


# Area weighted RMSE between trajectory a and trajectory b at every stored state
#   - distances[probe] is a timeseries with one value per stored state
function traj_distance(raw_dir_a, raw_dir_b, traj_a, traj_b; probes = keys(PROBES))

    with_raw_data(raw_dir_a, traj_a) do data_a
        with_raw_data(raw_dir_b, traj_b) do data_b

            # Area weights (npoints) and one container per probe
            aw = area_weights(data_a.spectral_grid)
            distances = NamedTuple{Tuple(probes)}(Tuple(Float64[] for _ in probes))

            # Both trajectories share the same sampling times
            for i_state in 0:data_a.n_states-1
                state_a, state_b = data_a[i_state], data_b[i_state]
                for probe in probes
                    field_a = Array(PROBES[probe].func(state_a))
                    field_b = Array(PROBES[probe].func(state_b))
                    push!(distances[probe], wrmse(field_a, field_b, aw))
                end
            end

            return (; sample_axis(data_a)..., metric = :rmse, distances...)
        end
    end
end










### 2) Error growth
###
### distances is a list of traj_distance results, one per trajectory pair

# Saturated RMSE of every probe: mean over the tail (day > day_min), then mean and std over trajectory pairs
function rmse_caps(distances, probes; day_min = 2500)

    # For each probe
    return NamedTuple{Tuple(probes)}(map(Tuple(probes)) do probe

        # Calculate tail means of traj_distance in distances for the current probe
        tail_means = [mean(distance[probe][distance.days .> day_min]) for distance in distances]

        # Calculate mean and std of all the tail means
        return (; mean = mean(tail_means), std = std(tail_means))
    end)
end


# Mean error-growth curve of every probe: mean and std over trajectory pairs at every stored day
function mean_curves(distances, probes)

    # For each probe
    return NamedTuple{Tuple(probes)}(map(Tuple(probes)) do probe

        # (day, pair) - one column per trajectory pair, all pairs share the same days
        curves_matrix = reduce(hcat, [distance[probe] for distance in distances])

        # Mean and std (and rms, n_valid) over trajectory pairs at every day
        return (; days = first(distances).days, traj_stats(curves_matrix)...)
    end)
end


# Exponential growth rate λ [1/day] of one probe and the doubling time [days] that follows from it,
#   - mean and std over trajectory pairs
#   - fit_days = (first day, last day) of the exponential fit
function growth_rate(distances, probe; fit_days)

    # Growth rate of every trajectory pair: slope of log(error) against time, inside the fit window
    rates = map(distances) do distance

        # Select days within the fit window
        in_fit  = (distance.days .>= fit_days[1]) .& (distance.days .<= fit_days[2])

        # Fit a linear model to the log of the error within the fit window
        _, rate = fit_linear(distance.days[in_fit], log.(distance[probe][in_fit]))

        return rate
    end

    # Doubling time of every trajectory pair
    doubling_times = log(2) ./ rates

    return (; λ        = (; mean = mean(rates),          std = std(rates)),
              doubling = (; mean = mean(doubling_times), std = std(doubling_times)))
end










### 3) Plotting

# Probe curves of raw-data results, one panel per probe, one line per result
function plot_probes(
    results,                    # global_means or traj_distance results
    probes;                     # probes, one panel each
    smooth_days = 0,            # running mean window in days (0 = raw curves only)
    yscale  = identity,         # identity or log10
    caps    = nothing,          # rmse_caps result, or nothing
    curves  = nothing,          # mean_curves result, or nothing
    title   = "",               # figure title
    style   = (;),              # entries of probes_style() to change
)

    # Check and merge styles 
    style = checked_merge(probes_style(), style)

    # Convert a single result to a one-element list if necessary
    results = results isa NamedTuple ? [results] : results

    # All results must show the same metric, the y-label is taken from the first one
    allequal(result.metric for result in results) || error("results mix metrics - plot global_means and traj_distance separately")

    # Extract number of panels and define figure
    n_panels = length(probes)
    fig = new_figure(style, n_panels; title)


    # One panel per probe
    for (i_panel, probe) in enumerate(probes)

        # Define probe panel
        ax = panel(fig, style, i_panel, n_panels;
                   xlabel = "lead time [days]", ylabel = axis_label(first(results).metric, probe), yscale)


        # One line per result
        for (i_result, result) in enumerate(results)

            # Color, samples and running mean window for the current result
            color   = style.colors[mod1(i_result, length(style.colors))]
            samples = yscale === identity ? result[probe] : positive(result[probe])
            window  = round(Int, smooth_days / result.gap_days)


            # Colorful running means and grey raw trajectories
            if 1 < window <= length(samples)
                lines!(ax, result.days, samples; color = (:grey, 0.25), linewidth = style.linewidth / 2)
                lines!(ax, running_mean(result.days, samples, window)...; color, linewidth = style.linewidth)
            
            # Colorful raw trajectory
            else
                lines!(ax, result.days, samples; color, linewidth = style.linewidth)
            end
        end

        # Plot RMSE caps and mean error growth curves (only meaningful for RMSE distances)
        if first(results).metric === :rmse
            isnothing(caps) ||
                hlines!(ax, [caps[probe].mean]; color = :black, linestyle = :dash, linewidth = 1.5 * style.linewidth)
            isnothing(curves) ||
                lines!(ax, curves[probe].days, curves[probe].mean; color = :black, linestyle = :solid, linewidth = 1.5 * style.linewidth)
        end
    end

    # Add a title
    add_title!(fig, style, title)

    return fig
end
