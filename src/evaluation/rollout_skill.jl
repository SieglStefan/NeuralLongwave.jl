### Rollout skill
###
### Ranks emulator on 14-day weather RMSE and computational cost in a plane






# Weather skill against runtime, one marker per unit (lower left = accurate and fast)
#   - x: weather RMSE ± standard error (weather_table)
#   - y: sweep time relative to the reference, error bar = 25 % - 75 % quantile of the per-round ratios (timing_table)
#   - marker: filled = climate check passed (or not checked), hollow = failed (climate_check_table),
#             black cross on top = a weather trajectory died (weather_table.dead)
function plot_weather_cost_plane(
    skill,                                  # weather_table
    timing;                                 # timing_table of the same units
    climate = nothing,                      # climate_check_table, or nothing (all markers filled)
    looks   = nothing,                      # appearance per unit (group joins units with a thin line)
    xlabel  = "weather: RMSE T [K]",        # must match probe and day of the weather_table
    ylabel  = "runtime LW / OBLW",
    title   = "",                           # figure title
    style   = (;),                          # entries of weather_cost_style() to change
)

    # Full style and figure
    style     = checked_merge(weather_cost_style(), style)
    n_entries = n_legend_entries(looks, skill.unit)
    fig       = new_figure(style, 1; title, n_entries)

    # One panel, runtime on a log axis if set (0.5 and 2 are equally far from 1)
    ax = panel(fig, style, 1, 1; xlabel, ylabel, yscale = style.y_log ? log10 : identity)

    # Reference runtime (OBLW)
    hlines!(ax, [1]; color = :gray, linestyle = :dash, linewidth = style.linewidth / 2)


    # Collect position, error bars and look of every unit
    points = map(enumerate(skill.unit)) do (i_unit, unit)

        # Timing row of the unit
        i_timing = findfirst(==(unit), timing.unit)
        isnothing(i_timing) && error("Unit $(unit) is not in the timing table!")
        t = timing[i_timing, :]

        # Climate check of the unit (a unit the table does not list counts as passed)
        i_climate = isnothing(climate) ? nothing : findfirst(==(unit), climate.unit)
        passed    = isnothing(i_climate) || climate.pass[i_climate]

        return (; x      = skill.weather_rmse[i_unit],
                  x_se   = skill.weather_se[i_unit],
                  y      = t.sweep_ratio,
                  y_lo   = t.sweep_ratio - t.sweep_ratio_lo,
                  y_hi   = t.sweep_ratio_hi - t.sweep_ratio,
                  passed = passed,
                  dead   = skill.dead[i_unit],
                  look   = look_of(looks, unit, i_unit, style))
    end


    # Thin line through every group, in the order of the table
    groups = unique(filter(!isnothing, [p.look.group for p in points]))
    for group in groups
        members = filter(p -> p.look.group == group, points)
        color   = something(style.trace_color, first(members).look.color)
        lines!(ax, [p.x for p in members], [p.y for p in members];
               color = (color, style.trace_alpha), linewidth = style.trace_width)
    end

    # One marker per unit, with error bars in both directions
    for p in points

        if style.errorbars
            errorbars!(ax, [p.x], [p.y], [p.x_se]; direction = :x, color = p.look.color)
            errorbars!(ax, [p.x], [p.y], [p.y_lo], [p.y_hi]; direction = :y, color = p.look.color)
        end

        # Filled marker if the climate check passed, hollow otherwise
        scatter!(ax, [p.x], [p.y]; marker = p.look.marker, markersize = p.look.markersize,
                 color = p.passed ? p.look.color : :white, strokecolor = p.look.color,
                 strokewidth = style.linewidth, label = p.look.label)

        # Black cross on top if a weather trajectory died
        p.dead && scatter!(ax, [p.x], [p.y]; color = :black, marker = :xcross, markersize = p.look.markersize)
    end

    # Weather RMSE axis starting at zero
    style.x_from_zero && xlims!(ax, 0, nothing)

    # Add legend and title to the figure
    add_legend!(fig, ax, style, 1, n_entries)
    add_title!(fig, style, title)

    return fig
end
