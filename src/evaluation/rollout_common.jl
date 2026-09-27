### Rollout common
###
### Utilities shared by the weather, climate and skill evaluation
###         - day_index       index of a stored lead day
###         - traj_stats      mean, std, rms, min, max and number of alive trajectories per row
###         - draw_curve!     one curve of one unit (mean, spread band, death marker)





# Index of a stored day
function day_index(days, day)

    # Find the index of the closest stored day to the requested day
    i_day = argmin(abs.(days .- day))

    # Throw error if closest stored day is too far from the requested day
    abs(days[i_day] - day) < 0.01 || error("day $(day) is not stored - stored days: $(round.(days, digits = 2))")

    return i_day
end



# Mean, spread, root mean square, min, max over trajectories and number of alive trajectories at every row
#   - traj_values is of shape (row, traj), rows are e.g. time, layer or ring
#   - NaN entries are trajectories that blew up, they are left out; n_valid says how many were left
function traj_stats(traj_values)

    # Finite values of every row: one vector per row, shorter once trajectories have died
    filtered_rows = [filter(isfinite, view(traj_values, i_row, :)) for i_row in axes(traj_values, 1)]

    # Statistics over the alive trajectories of every row
    return (; 
        mean    = [isempty(alive) ? NaN : Float64(mean(alive)) for alive in filtered_rows],
        std     = [length(alive) > 1 ? Float64(std(alive)) : 0.0 for alive in filtered_rows],
        rms     = [isempty(alive) ? NaN : sqrt(Float64(mean(abs2, alive))) for alive in filtered_rows],
        n_valid = length.(filtered_rows),
        min     = [isempty(alive) ? NaN : Float64(minimum(alive)) for alive in filtered_rows],
        max     = [isempty(alive) ? NaN : Float64(maximum(alive)) for alive in filtered_rows],
    )
end



# One curve against time of one unit: the mean, its spread as a band, and a dotted line where it starts exploding
#   - a curve is of form (; days, mean, std, rms, n_valid) 
function draw_curve!(ax, curve, look, style; n_traj)

    # Spread, only where the mean exists
    has_mean = isfinite.(curve.mean)

    # Draw the spread band if requested, 
    if style.band && any(has_mean)

        # Band according to style.band_kind
        #   - :minmax  range of the trajectories (few trajectories, e.g. climate)
        #   - :se      ± standard error of the mean (many trajectories, e.g. weather)
        #   - :std     ± standard deviation of the trajectories
        if style.band_kind === :minmax
            lower, upper = curve.min, curve.max
        elseif style.band_kind === :se
            standard_error = curve.std ./ sqrt.(curve.n_valid)
            lower, upper   = curve.mean .- standard_error, curve.mean .+ standard_error
        elseif style.band_kind === :std
            lower, upper = curve.mean .- curve.std, curve.mean .+ curve.std
        else
            error("unknown band_kind $(style.band_kind) - use :se, :minmax or :std")
        end

        # Draw band
        band!(ax, curve.days[has_mean], lower[has_mean], upper[has_mean];
              color = (look.color, style.band_alpha))
    end

    # Draw lines
    lines!(ax, curve.days, curve.mean; color = look.color, linestyle = look.linestyle,
           linewidth = style.linewidth, label = look.label)

    # Vertical line where the first trajectory died (at the window start if it died before)
    i_death = findfirst(<(n_traj), curve.n_valid)
    isnothing(i_death) ||
            vlines!(ax, [curve.days[i_death]]; color = look.color, linestyle = :dash, linewidth = style.linewidth)

            
    return nothing
end
