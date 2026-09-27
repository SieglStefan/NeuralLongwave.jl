### Evaluation styles
###
### Utilities for defining plot styles and helper functions
###         - 1) Colors
###         - 2) Styles
###         - 3) Axes Labels
###         - 4) Merging defaults and looks
###         - 5) Figure layout










### 1) Colors

# General colors used across all evaluations
const JL_BLUE   = RGBf(0.251, 0.388, 0.847)
const JL_GREEN  = RGBf(0.220, 0.596, 0.149)
const JL_RED    = RGBf(0.796, 0.235, 0.200)
const JL_PURPLE = RGBf(0.584, 0.345, 0.698)

# One color per loss field, in every plot that draws one line per field
const FIELD_COLORS = (; T = JL_RED, olw = JL_BLUE, slwd = JL_GREEN, dT = JL_PURPLE)










### 2) Styles
###
### Every *_style() starts from base_style() and lists ONLY what it changes or adds. Every field that
### is not in base_style() is read by the plot functions named above the style.
###     - keys a notebook may change via style = (; ...) must exist here (checked_merge)

# Default look of every figure
base_style() = (;
    textwidth_cm = 30.0,        # width of the LaTeX text block - change once the template is known
    width        = 1.0,         # figure width, as a fraction of the text width
    aspect       = 0.8,         # panel height / panel width
    ncols        = 3,           # panels per row
    fontsize     = 13,          # every text, in pt
    linewidth    = 2,           # in pt
    legend       = :right,      # :bottom, :right or :none
    legend_cols  = 3,           # legend entries per row (legend = :bottom)
    markersize   = 7,           # in pt
    colors       = (JL_BLUE, JL_GREEN, JL_RED, JL_PURPLE, :orange, :cyan, :magenta, :brown),
)


# Raw data: plot_probes - one line per trajectory (pair), so no legend
probes_style() = merge(base_style(), (;
    ncols  = 2,
    aspect = 0.6,
    legend = :none,
))


# Dataset: plot_correlation
correlation_style() = merge(base_style(), (;
    ncols       = 4,
    fontsize    = 11,
    linewidth   = 1.2,
    legend      = :none,
    n_points    = 3000,         # points drawn per panel (R^2 uses all of them)
    point_size  = 2,
    point_alpha = 0.2,
))


# Dataset: plot_hist
hist_style() = merge(base_style(), (;
    ncols      = 4,
    fontsize   = 11,
    linewidth  = 1.2,
    legend     = :none,
    bins       = 30,
    hist_color = (JL_BLUE, 0.8),
))


# Training: plot_training
training_style() = merge(base_style(), (;
    aspect    = 1.0,
    raw_alpha = 0.3,            # unsmoothed curve behind the smoothed one
))


# Training: plot_loss_shares (one run)
shares_style() = merge(base_style(), (;
    width = 0.5,
    ncols = 1,
))


# Training: plot_rmse
rmse_style() = merge(base_style(), (;
    aspect = 1.0,
))


# Weather: plot_weather_growth
growth_style() = merge(base_style(), (;
    band       = true,          # uncertainty of the mean curve
    band_alpha = 0.15,
    band_kind  = :se,           # ± standard error (many trajectories)
))


# Weather: plot_weather_profile
profile_style() = merge(base_style(), (;
    aspect     = 1.3,           # tall panels, the vertical axis is the atmosphere
    band       = false,         # trajectory spread as error bars
    markersize = 5,
))


# Weather-cost plane: plot_weather_cost_plane (weather RMSE against runtime)
weather_cost_style() = merge(base_style(), (;
    width       = 0.8,
    ncols       = 1,
    fontsize    = 16,
    markersize  = 15,
    errorbars   = true,         # ± SE (RMSE) and 25 - 75 % quantile (runtime)
    zero_rmse   = true,         # create dashed line at zero rmse
    y_log       = false,        # runtime axis logarithmic (true: 0.5 and 2 equally far from 1)
    trace_color = :black,       # line through a group (nothing = the group's color)
    trace_width = 1.5,
    trace_alpha = 0.5,
    xlim        = nothing,
    ylim        = nothing
))


# Climate: plot_climate_drift
drift_style() = merge(base_style(), (;
    ncols      = 2,
    aspect     = 0.6,
    band       = true,          # trajectory spread
    band_alpha = 0.15,
    band_kind  = :minmax,       # range of the trajectories (few trajectories)
))


# Climate: plot_climate_bias
bias_style() = merge(base_style(), (;
    ncols      = 2,
    legend     = :none,         # units are on the y-axis
    markersize = 10,
))


# Heatmaps: the colors of every lon/lat map and zonal section (base of lonlat_style and zonal_style)
heatmap_style() = merge(base_style(), (;
    legend             = :none,
    signed_colormap    = :balance,      # bias
    magnitude_colormap = :thermal,      # rmse, maxdiff
))


# Maps: plot_lonlat
lonlat_style() = merge(heatmap_style(), (;
    ncols           = 3,
    aspect          = 0.55,             # lon/lat panel plus its title
    ticklabels      = false,            # lon/lat tick labels
    coastline_width = 0.5,
))


# Sections: plot_zonal (plot_weather_zonal, plot_climate_zonal)
zonal_style() = merge(heatmap_style(), (;
    textwidth_cm = 30.0,
    ncols        = 3,
    aspect       = 0.6,
))










### 3) Axes Labels

# Display names, the symbols stay lowercase everywhere, only the text a reader sees changes
#   - if not listet, no changes to variable name (e.g: T -> "T")
probe_label(probe) = string(get((; olw = "OLW", slwd = "SLWD", sst = "SST", imb_TOA = "TOA imbalance"), probe, probe))

metric_label(metric) = string(get((; mean = "global mean", rmse = "RMSE", bias = "bias",
                                     maxdiff = "max |Δ|"), metric, metric))

# Axis label of one metric of one probe, e.g. "RMSE OLW [W/m²]"
axis_label(metric, probe) = "$(metric_label(metric)) $(probe_label(probe)) [$(PROBES[probe].unit)]"










### 4) Merging defaults and looks

# How a given unit is drawn: every entry is optional, units that looks does not list get defaults from style
#
# Example:
#     looks = (;
#         direct_w064_h3 = (; label = "Direct W64 H3", color = JL_BLUE),
#         linear_w064_h3 = (; label = "Linear W64 H3", color = JL_GREEN, linestyle = :dot),
#     )
#
#   - i_unit is the position of the unit in the plotted data, it picks the default color
#   - group joins units with a thin line in the weather-cost plane
#   - unit can be a symbol or string, e.g.: :direct_w064_h3 or "direct_w064_h3"
function look_of(looks, unit, i_unit, style)

    # Define defaults
    defaults = (; label      = string(unit),
                  color      = style.colors[mod1(i_unit, length(style.colors))],
                  linestyle  = :solid,
                  marker     = :circle,
                  markersize = style.markersize,
                  group      = nothing)

    # Extract style of given unit from looks
    given = isnothing(looks) ? (;) : get(looks, Symbol(unit), (;))

    # Return merged styles of the unit (given has priority)
    return checked_merge(defaults, given)
end


# Name of the units in the legend, in order
unit_names(looks, units) = [look_of(looks, unit, i_unit, base_style()).label for (i_unit, unit) in enumerate(units)]

# Number of distinct entries in a legend
n_legend_entries(looks, units) = length(unique(unit_names(looks, units)))










### 5) Figure layout

# Panel grid of n_panels panels: (columns, rows)
grid_shape(style, n_panels) = (nc = min(style.ncols, n_panels); (nc, cld(n_panels, nc)))


# Position (row, column) of every panel and the grid size (columns, rows)
#   - layout = nothing:     panels filled row by row, style.ncols per row
#   - layout = 0/1 matrix:  panels fill the 1-cells row by row, e.g. [0 1 0; 1 1 1; 1 1 1]
function panel_positions(style, n_panels; layout = nothing)

    # Default: row by row
    if isnothing(layout)
        nc, nr = grid_shape(style, n_panels)
        return [(cld(i_panel, nc), mod1(i_panel, nc)) for i_panel in 1:n_panels], nc, nr
    end

    # Custom layout: the 1-cells, row by row
    positions = [(row, col) for row in axes(layout, 1) for col in axes(layout, 2) if layout[row, col] == 1]
    length(positions) == n_panels || error("layout has $(length(positions)) panels, but there are $(n_panels) to plot")

    return positions, size(layout, 2), size(layout, 1)
end


# Empty figure for n_panels panels
function new_figure(style, n_panels; title = "", n_entries = 0, shape = grid_shape(style, n_panels))

    # Number of columns and rows (shape = (columns, rows), e.g. from panel_positions)
    nc, nr = shape

    # Width is fixed by page, height follows from the panel aspect ratio
    w = style.width * style.textwidth_cm / 2.54 * 72
    h = nr * style.aspect * w / nc

    # Extra lines of text are reserved for the title and for a legend below the panels
    extra = (isempty(title) ? 0 : 2) + (style.legend === :bottom ? 4.0 * cld(n_entries, style.legend_cols) : 0)
    h += extra * style.fontsize

    # Makie wants whole units
    return Figure(; size = round.(Int, (w, h)), fontsize = style.fontsize)
end


# Axis of panel i_panel, panels filled row by row (axis_type = GeoMakie.GeoAxis for maps)
#   - position = (row, column) places the panel explicitly (e.g. from panel_positions)
function panel(fig, style, i_panel, n_panels; axis_type = Axis, position = nothing, kwargs...)

    # Number of columns for the grid of panels
    nc, _ = grid_shape(style, n_panels)

    # Row and column of the panel
    row, col = isnothing(position) ? (cld(i_panel, nc), mod1(i_panel, nc)) : position

    # Return panel
    return axis_type(fig[row, col]; kwargs...)
end


# Legend of everything labeled in ax, below the panels or to their right
function add_legend!(fig, ax, style, n_panels, n_entries)

    # No legend
    (style.legend === :none || n_entries == 0) && return nothing

    # Number of columns and rows for the grid of panels
    nc, nr = grid_shape(style, n_panels)

    # Add the legend either to the right or below the panels depending on the style setting
    style.legend === :right &&
        return Legend(fig[1:nr, nc+1], ax; merge = true, unique = true, framevisible = false)

    return Legend(fig[nr+1, 1:nc], ax; merge = true, unique = true, framevisible = false,
                  orientation = :horizontal, nbanks = cld(n_entries, style.legend_cols))
end


# Figure title above all panels
function add_title!(fig, style, title)

    # No title
    isempty(title) && return nothing

    # Return title
    return Label(fig[0, :], title; font = :bold, fontsize = style.fontsize + 1)
end


# Values a log axis can show - everything else becomes NaN, which Makie skips
positive(samples) = [sample > 0 ? Float64(sample) : NaN for sample in samples]










