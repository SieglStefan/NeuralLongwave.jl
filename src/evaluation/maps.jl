### Maps
###
### Global maps (lon/lat) and zonal cross sections (latitude x layer): one panel per field, one shared colorbar.
###         - 1) Helpers
###         - 2) Plotting










### 1) Helpers

# Shared color range of several fields (colorrange = a fixed (low, high) range)
function color_scale(fields, signed, style; colorrange = nothing)

    # Return colorrange if already provided
    isnothing(colorrange) || return colorrange, (signed ? style.signed_colormap : style.magnitude_colormap)

    # List of maxima of all values of all fields in fields
    max_value = maximum(abs, (value for field in fields for value in field if isfinite(value)); init = 0.0)

    # Largest finite magnitude of all fields
    max_abs = max(max_value, eps(Float32))

    # Choose and returned signed or unsigned boundaries
    return signed ? ((-max_abs, max_abs), style.signed_colormap) : ((0, max_abs), style.magnitude_colormap)
end


# Lon/lat matrix of a grid-point vector (npoints), longitudes shifted to [-180, 180]
function lonlat_matrix(grid_values, grid)

    # Interpolate onto the full (regular) grid of the same resolution
    full_field = RingGrids.interpolate(RingGrids.full_grid_type(grid), grid.nlat_half, Field(grid_values, grid))

    # Longitudes from [0, 360] to [-180, 180], sorted
    lons  = [lon > 180 ? lon - 360 : lon for lon in RingGrids.get_lond(full_field)]
    order = sortperm(lons)

    # Return longitudes, latitudes and (sorted) field matrix
    return lons[order], RingGrids.get_latd(full_field), Matrix(full_field)[order, :]
end










### 2) Plotting

# Global maps of several grid-point vectors, one panel per field
function plot_lonlat(
    fields,                 # grid-point vectors (npoints), one panel each
    grid;                   # grid of the fields
    titles,                 # panel titles
    signed,                 # true = diverging scale around zero
    label,                  # colorbar label
    title = "",             # figure title
    colorrange = nothing,   # fixed (low, high) color range (nothing = from the data)
    layout = nothing,       # panel layout, 0/1 matrix e.g. [0 1 0; 1 1 1] (nothing = row by row, style.ncols)
    style = (;),            # entries of lonlat_style() to change
)

    # Full style, panel positions, figure and one color scale for all panels
    style    = checked_merge(lonlat_style(), style)
    n_panels = length(fields)
    positions, nc, nr = panel_positions(style, n_panels; layout)
    fig      = new_figure(style, n_panels; title, shape = (nc, nr))

    # Define colorrange and color
    colorrange, colormap = color_scale(fields, signed, style; colorrange)


    # One panel per field, coastlines on top
    heatmap_plot = nothing
    for (i_panel, field) in enumerate(fields)

        # Define lonlat and calculate full field matrix
        lons, lats, matrix = lonlat_matrix(field, grid)

        # Define panel
        ax = panel(fig, style, i_panel, n_panels; position = positions[i_panel], axis_type = GeoMakie.GeoAxis, dest = "+proj=longlat",
                   title = titles[i_panel], xgridvisible = false, ygridvisible = false,
                   xticklabelsvisible = style.ticklabels, yticklabelsvisible = style.ticklabels)

        # Plot heatmap and draw coastline
        heatmap_plot = heatmap!(ax, lons, lats, matrix; colorrange, colormap)
        lines!(ax, GeoMakie.coastlines(); color = :black, linewidth = style.coastline_width)
    end

    # Add colorbar and title to the figure
    Colorbar(fig[1:nr, nc+1], heatmap_plot; label)
    add_title!(fig, style, title)

    return fig
end


# Zonal cross sections (ring, layer) of several fields, one panel per field
function plot_zonal(
    sections,               # (ring, layer) matrices, one panel each
    latd;                   # ring latitudes
    titles,                 # panel titles
    signed,                 # true = diverging scale around zero
    label,                  # colorbar label
    title = "",             # figure title
    colorrange = nothing,   # fixed (low, high) color range (nothing = from the data)
    layout = nothing,       # panel layout, 0/1 matrix e.g. [0 1 0; 1 1 1] (nothing = row by row, style.ncols)
    style = (;),            # entries of zonal_style() to change
)

    # Full style, panel positions, figure and one color scale for all panels
    style    = checked_merge(zonal_style(), style)
    n_panels = length(sections)
    positions, nc, nr = panel_positions(style, n_panels; layout)
    fig      = new_figure(style, n_panels; title, shape = (nc, nr))

    # Define colorrange and color
    colorrange, colormap = color_scale(sections, signed, style; colorrange)


    # One panel per section, layer 1 (top of the atmosphere) at the top
    heatmap_plot = nothing
    for (i_panel, section) in enumerate(sections)

        # Define layers
        layers = collect(axes(section, 2))

        # Define panel
        ax = panel(fig, style, i_panel, n_panels; position = positions[i_panel],
                   title = titles[i_panel], xlabel = "latitude [°]", ylabel = "layer",
                   xticks = -90:30:90, yticks = layers, yreversed = true)

        # Plot heatmap
        heatmap_plot = heatmap!(ax, latd, layers, section; colorrange, colormap)
    end

    # Add colorbar and title to the figure
    Colorbar(fig[1:nr, nc+1], heatmap_plot; label)
    add_title!(fig, style, title)

    return fig
end
