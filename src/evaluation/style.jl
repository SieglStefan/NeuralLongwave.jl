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

# Default look of every figure
base_style() = (;
    textwidth_cm = 15.0,        # width of the LaTeX text block - change once the template is known
    width        = 1.0,         # figure width, as a fraction of the text width
    aspect       = 0.8,         # panel height / panel width
    ncols        = 3,           # panels per row
    fontsize     = 9,           # every text, in pt
    linewidth    = 1.2,         # in pt
    legend       = :bottom,     # :bottom, :right or :none
    legend_cols  = 3,           # legend entries per row (legend = :bottom)
    markersize   = 7,           # in pt
    colors     = (JL_BLUE, JL_GREEN, JL_RED, JL_PURPLE, :orange, :cyan, :magenta, :brown),
)


# Raw data: plot_probes - one line per IC, so no legend
probes_style() = merge(base_style(), (;
    legend = :none,
    ncols = 2,
))


# Dataset: plot_correlation
correlation_style() = merge(base_style(), (;
    ncols       = 2,
    legend      = :none,
    n_points    = 3000,         # points drawn per panel (R^2 uses all of them)
    point_size  = 2,
    point_alpha = 0.2,
))


# Dataset: plot_hist
hist_style() = merge(base_style(), (;
    ncols      = 2,
    legend     = :none,
    bins       = 30,
    hist_color = (JL_BLUE, 0.8),
))


# Training: plot_training
training_style() = merge(base_style(), (;
    raw_alpha = 0.3,            # opacity of the raw loss behind its block mean
))


# Training: plot_loss_shares (one run)
shares_style() = merge(base_style(), (;
    width  = 0.5,
    ncols  = 1,
))


# Training: plot_rmse
rmse_style() = merge(base_style(), (;
    ncols = 4,
))


# Heatmaps: the colors of every lon/lat map and zonal section
heatmap_style() = merge(base_style(), (;
    legend             = :none,
    signed_colormap    = :balance,      # bias
    magnitude_colormap = :thermal,      # rmse, rmsb, maxdiff
))


# Maps: plot_climate_lonlat
lonlat_style() = merge(heatmap_style(), (;
    aspect          = 0.55,             # lon/lat panel plus its title
    ticklabels      = false,            # lon/lat tick labels
    coastline_width = 0.5,
))


# Weather: plot_weather_growth
growth_style() = merge(base_style(), (;
    band       = true,          # trajectory spread
    band_alpha = 0.15,
))


# Weather: plot_weather_profile
profile_style() = merge(base_style(), (;
    aspect     = 1.3,           # tall panels, the vertical axis is the atmosphere
    band       = false,         # trajectory spread as error bars
    markersize = 5,
))


# Sections: plot_weather_zonal, plot_climate_zonal
zonal_style() = merge(heatmap_style(), (;
    aspect = 0.8,
))


# Climate: plot_climate_drift
drift_style() = merge(base_style(), (;
    ncols      = 2,
    aspect     = 0.6,
    band       = true,          # trajectory spread (bias only)
    band_alpha = 0.15,
))


# Skill plane: plot_skill_plane
skill_style() = merge(base_style(), (;
    width       = 0.8,
    ncols       = 1,
    legend      = :right,
    trace_color = nothing,      # line through a group (nothing = the group's color)
    trace_width = 1.5,
    trace_alpha = 0.5,
))










### 3) Axes Labels

# Display names, the symbols stay lowercase everywhere, only the text a reader sees changes
#   - if not listet, no changes to variable name (e.g: T -> "T")
probe_label(probe) = string(get((; olw = "OLW", slwd = "SLWD", sst = "SST", imb_TOA = "TOA imbalance"), probe, probe))

metric_label(metric) = string(get((; mean = "global mean", rmse = "RMSE", bias = "bias",
                                     maxdiff = "max |Δ|", rmsb = "RMSB"), metric, metric))

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
#   - group joins units with a thin line in the skill plane
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


# Empty figure for n_panels panels
function new_figure(style, n_panels; title = "", n_entries = 0)

    # Number of columns and rows
    nc, nr = grid_shape(style, n_panels)

    # Width is fixed by page, height follows from the panel aspect ratio
    w = style.width * style.textwidth_cm / 2.54 * 72
    h = nr * style.aspect * w / nc

    # Extra lines of text are reserved for the title and for a legend below the panels
    extra = (isempty(title) ? 0 : 2) + (style.legend === :bottom ? 1.5 * cld(n_entries, style.legend_cols) : 0)
    h += extra * style.fontsize

    # Makie wants whole units
    return Figure(; size = round.(Int, (w, h)), fontsize = style.fontsize)
end


# Axis of panel i_panel, panels filled row by row (axis_type = GeoMakie.GeoAxis for maps)
function panel(fig, style, i_panel, n_panels; axis_type = Axis, kwargs...)

    # Number of columns for the grid of panels
    nc, _ = grid_shape(style, n_panels)

    # Return panel
    return axis_type(fig[cld(i_panel, nc), mod1(i_panel, nc)]; kwargs...)
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










