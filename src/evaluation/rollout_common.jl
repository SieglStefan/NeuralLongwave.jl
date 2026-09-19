### Rollout common
###
### Utilities shared by the weather, climate and skill evaluation
###         - day_index       index of a stored lead day
###         - traj_stats      mean, std, rms and number of alive trajectories per row
###         - draw_curve!     one curve of one unit (mean, spread band, death marker)





# Index of a stored day
function day_index(days, day)

    # Find the index of the closest stored day to the requested day
    i_day = argmin(abs.(days .- day))

    # Throw error if closest stored day is too far from the requested day
    abs(days[i_day] - day) < 0.01 || error("day $(day) is not stored - stored days: $(round.(days, digits = 2))")

    return i_day
end



# Mean, spread, root mean square over trajectories and number of alive trajectories at every row
#   - traj_values is of shape (row, traj): one value (a score or a bias) per row (e.g. time, layer or ring) and trajectory
#   - NaN entries are trajectories that blew up, they are left out; n_valid says how many were left
function traj_stats(traj_values)

    # Finite values of every row: one vector per row, shorter once trajectories have died
    filtered_rows = [filter(isfinite, view(traj_values, i_row, :)) for i_row in axes(traj_values, 1)]

    # Statistics over the alive trajectories of every row
    return (; mean    = [isempty(alive) ? NaN : Float64(mean(alive)) for alive in filtered_rows],
              std     = [length(alive) > 1 ? Float64(std(alive)) : 0.0 for alive in filtered_rows],
              rms     = [isempty(alive) ? NaN : sqrt(Float64(mean(abs2, alive))) for alive in filtered_rows],
              n_valid = length.(filtered_rows))
end



# One curve of one unit: the mean, its spread as a band, and a dotted line where it starts losing
# trajectories (std and n_valid are optional)
#   - value = :rms draws the root mean square over trajectories instead of the mean, without a band
#   - a curve is of form (; days, mean, std, rms, n_valid) 
function draw_curve!(ax, curve, look, style; value = :mean, n_traj)

    # Spread, only where the mean exists
    has_mean = isfinite.(curve.mean)
    if value === :mean && style.band && haskey(curve, :std) && any(has_mean)
        band!(ax, curve.days[has_mean],
              curve.mean[has_mean] .- curve.std[has_mean], curve.mean[has_mean] .+ curve.std[has_mean];
              color = (look.color, style.band_alpha))
    end

    # Mean (or the statistic chosen by value)
    lines!(ax, curve.days, curve[value]; color = look.color, linestyle = look.linestyle,
           linewidth = style.linewidth, label = look.label)

    # First shown point with fewer alive trajectories than the rollout has (the window start if one died before it)
    if haskey(curve, :n_valid) && !isempty(curve.n_valid)
        i_death = findfirst(<(n_traj), curve.n_valid)
        isnothing(i_death) ||
            vlines!(ax, [curve.days[i_death]]; color = look.color, linestyle = :dot, linewidth = style.linewidth / 2)
    end

    return nothing
end
