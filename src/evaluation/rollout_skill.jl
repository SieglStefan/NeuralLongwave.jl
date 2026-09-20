### Rollout skill
###
### Checks the reference and ranks units on both legs at once, with weather_skill (rollout_weather.jl)
### and climate_skill (rollout_climate.jl)
###         - 1) Reference check
###         - 2) Skill table
###         - 3) Skill plane
###
### Skill plane scores (mean over trajectories ± standard error = std / sqrt(alive trajectories)):
###         - weather_rmse ± weather_se:    RMSE of the probe (all grid points and layers) at the lead day
###         - climate_bias ± climate_se:    global, year-mean bias of the probe (warming or cooling)
###
### Context:
###         - weather_rmse_early:       th same RMSE at an early lead day (mostly the emulator's own error)
###         - climate_rmsb:             rms over trajectories of the same global, year-mean bias (one number that
###                                         penalizes drift and spread, e.g. for sorting the table)
###         - imb_TOA_bias:             the same bias of the TOA energy imbalance, once the run has re-equilibrated,
###                                         a conserving emulator is back at the reference imbalance, so what remains
###                                         is energy the emulator creates or destroys
###         - xxx_alive / xxx_n_traj:   trajectories still alive at the scored day / year, the scores only cover those
###         - survived_days:            shortest climate trajectory in days










### 1) Reference check

# Checks if a rollout against the TARGET scheme is exactly zero against its own reference over the whole rollout
#   - anything else means, that there is an error in the rollout generation or related code
function test_reference(rollout; tol = 1f-6)

    # One row per probe, all trajectories summarized
    table = DataFrame(probe = Symbol[], max_error = Float64[], n_exact = Int[], n_traj = Int[], failed_ics = Vector{Int}[])
    
    # Loop over probes
    for probe in rollout.probes

        # Choose different test metric (weather: rmse, climate: bias) for different legs
        errors = rollout.leg === :weather ? rollout.scores[probe].rmse :
                                            rollout.global_mean_run[probe] .- rollout.global_mean_ref[probe]

        # Collect all maximum errors for all trajectories
        traj_errors = [Float64(maximum(abs, view(errors, :, :, traj))) for traj in axes(errors, 3)]

        # Select errors which are smaller than the given tolerance
        exact = traj_errors .<= tol

        # Summary of the probe: largest error, number of exact trajectories and the ICs of the others
        push!(table, (; probe,
                        max_error  = maximum(traj_errors),
                        n_exact    = count(exact),
                        n_traj     = length(exact),
                        failed_ics = sort(unique(rollout.traj_ic[.!exact]))))
    end

    # Report the result
    if all(table.n_exact .== table.n_traj)
        @info "Reference reproduced exactly for every probe and trajectory."
    else
        @warn "Reference NOT reproduced for IC $(sort(unique(reduce(vcat, table.failed_ics)))) - every score carries this offset."
    end

    return table
end










### 2) Skill table

# One row per unit, in the order of the input
#   - weather and climate must list the same units in the same order
function skill_table(
    ro_weather,             # weather rollouts, keyed by unit
    ro_climate;             # climate rollouts, keyed by unit
    probe     = :T,         # ranked probe
    day       = 14,         # weather lead day
    early_day = 1,          # weather lead day of the context column
    year      = 3,          # climate year
)

    # Check if both legs list the same units
    keys(ro_climate) == keys(ro_climate) || error("Weather and climate rollouts must list the same units in the same order")

    # Scores and survival of every unit
    table = DataFrame(map(collect(keys(weather))) do unit

        # Skill numbers of both legs
        weather_score = weather_skill(ro_weather[unit]; probe, day)
        weather_early = weather_skill(ro_weather[unit]; probe, day = early_day)
        climate_score = climate_skill(ro_climate[unit]; probe, year)
        energy_score  = climate_skill(ro_climate[unit]; probe = :imb_TOA, year)

        return (; unit               = string(unit),

                  # Skill plane scores (mean ± standard error over trajectories)
                  weather_rmse       = weather_score.rmse,
                  weather_se         = weather_score.std / sqrt(weather_score.n_valid),
                  climate_bias       = climate_score.bias,
                  climate_se         = climate_score.std / sqrt(climate_score.n_valid),

                  # Context
                  weather_rmse_early = weather_early.rmse,
                  climate_rmsb       = climate_score.rmsb,
                  imb_TOA_bias       = energy_score.bias,

                  # Survival
                  weather_alive      = weather_score.n_valid,
                  weather_n_traj     = length(weather[unit].traj_ic),
                  climate_alive      = climate_score.n_valid,
                  climate_n_traj     = length(climate[unit].traj_ic),
                  survived_days      = Float64(minimum(climate[unit].survived_days)))
    end)

    # A unit is dead if any of its trajectories died during rollout
    table.dead = (table.weather_alive .< table.weather_n_traj) .| (table.climate_alive .< table.climate_n_traj)

    return table
end










### 3) Skill plane

# Skill Plane: Weather RMSE vs. Climate Bias, one marker with error bars (± standard error) per unit of a skill_table
#   - a grey zero line marks no climate drift
#   - units sharing a look group are joined by a thin line, in table order
#   - units with a dead trajectory (weather or climate) get a cross on top of their own marker
function plot_skill_plane(
    table;                      # skill_table generated by skill_table()
    looks  = nothing,           # appearance per unit (group joins units)
    xlabel = "weather RMSE",    # x-axis label
    ylabel = "climate bias",    # y-axis label
    title  = "",                # figure title
    style  = (;),               # entries of skill_style() to change
)

    # Plane axes: mean ± standard error over trajectories
    x, x_err = table.weather_rmse, table.weather_se
    y, y_err = table.climate_bias, table.climate_se

    # Full style, looks and figure
    style      = checked_merge(skill_style(), style)
    unit_looks = [look_of(looks, unit, i_unit, style) for (i_unit, unit) in enumerate(table.unit)]
    n_entries  = length(unique(look.label for look in unit_looks)) + any(table.dead)
    fig        = new_figure(style, 1; title, n_entries)

    # Define panel
    ax = panel(fig, style, 1, 1; xlabel, ylabel)

    # Zero line of the signed climate axis
    hlines!(ax, [0]; color = :gray, linestyle = :dash, linewidth = style.linewidth / 2)

    # Thin line through the units of every group
    for group in unique(look.group for look in unit_looks if !isnothing(look.group))
        members = findall(look -> look.group == group, unit_looks)
        lines!(ax, x[members], y[members];
               color = (something(style.trace_color, unit_looks[members[1]].color), style.trace_alpha),
               linewidth = style.trace_width)
    end

    # One marker with error bars per unit, a cross on top of the dead ones
    for (i_unit, look) in enumerate(unit_looks)
        errorbars!(ax, [x[i_unit]], [y[i_unit]], [x_err[i_unit]]; direction = :x, color = look.color,
                   linewidth = style.linewidth / 2)
        errorbars!(ax, [x[i_unit]], [y[i_unit]], [y_err[i_unit]]; direction = :y, color = look.color,
                   linewidth = style.linewidth / 2)
        scatter!(ax, [x[i_unit]], [y[i_unit]];
                 color = look.color, marker = look.marker, markersize = look.markersize, label = look.label)
        table.dead[i_unit] && scatter!(ax, [x[i_unit]], [y[i_unit]]; color = :black, marker = :xcross,
                                       markersize = look.markersize, label = "≥1 trajectory died")
    end

    # The weather RMSE is >= 0, so its axis starts at zero (the climate bias is signed)
    xlims!(ax; low = 0)

    # Units without a position are only reported - they belong in the caption
    not_drawn = table.unit[.!(isfinite.(x) .& isfinite.(y))]
    isempty(not_drawn) || @warn "not drawn (non-finite score): $(not_drawn)"

    # Add a legend and title to the figure
    add_legend!(fig, ax, style, 1, n_entries)
    add_title!(fig, style, title)

    return fig
end
