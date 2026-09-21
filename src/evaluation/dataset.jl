### Dataset evaluation
###
### Diagnostics of the column_io dataset (derive_column_io) and its z-score stats (derive_zscore).
###         - 1) Helpers
###         - 2) Plotting
###
### Plot possibilities:
###     - plot_correlation      how well T predicts a target, per layer
###     - plot_hist             how the z-scored values are distributed
###
### Dataset fields are (npoints, nlayers, n_states) for profiles and (npoints, n_states) for scalars.










### 1) Helpers

# Number of layers of a dataset field
n_layers(field) = ndims(field) == 3 ? size(field, 2) : 1

# Layer k of a dataset field, flattened over points and states
flat_layer(field, k) = ndims(field) == 3 ? vec(view(field, :, k, :)) : vec(field)

# Name of layer k of a dataset field (for plotting)
layer_name(field, name, k) = ndims(field) == 3 ? "$(name)[$(k)]" : string(name)

# Thin out samples (for a readable scatter plot)
thin_sample(samples, n_max) = length(samples) <= n_max ? samples : samples[round.(Int, range(1, length(samples), length = n_max))]










### 2) Plotting

# Scatter plot of a target against predictors, with a fitted line and its R^2, one panel per layer
function plot_correlation(
    data,                           # column_io.fields
    target_name,                    # target, e.g. :dT
    predictor_names;                # predictor(s), e.g. :T or (:T, :ps)
    output_form = LinearOutput(),   # decides the T predictor
    title       = "",               # figure title
    style       = (;),              # entries of correlation_style() to change
)

    # Full style, and a single predictor as a one-element tuple
    style           = checked_merge(correlation_style(), style)
    predictor_names = predictor_names isa Symbol ? (predictor_names,) : predictor_names

    # Target field and predictor fields (T through the output form)
    target     = data[target_name]
    predictors = map(name -> name === :T ? something(pred(output_form, data[:T]), data[:T]) : data[name],
                     predictor_names)


    # One (predictor, layer) per panel
    panels   = [(i_pred, k) for i_pred in eachindex(predictor_names)
                for k in 1:max(n_layers(target), n_layers(predictors[i_pred]))]
    n_panels = length(panels)
    fig      = new_figure(style, n_panels; title)

    # One panel per (predictor, layer)
    for (i_panel, (i_pred, k)) in enumerate(panels)

        # Finite pairs of this layer
        x, y   = flat_layer(predictors[i_pred], k), flat_layer(target, k)
        finite = isfinite.(x) .& isfinite.(y)
        x, y   = x[finite], y[finite]

        # Fitted line and its R^2, on ALL points
        intercept, slope = fit_linear(x, y)
        r2 = 1 - sum(abs2, y .- (intercept .+ slope .* x)) / sum(abs2, y .- mean(y))


        # Define panel
        ax = panel(fig, style, i_panel, n_panels;
                   xlabel = layer_name(predictors[i_pred], predictor_names[i_pred], k),
                   ylabel = layer_name(target, target_name, k))

        # Draw scatter points, draw regression line and display R^2
        scatter!(ax, thin_sample(x, style.n_points), thin_sample(y, style.n_points);
                 color = (:black, style.point_alpha), markersize = style.point_size)
        lines!(ax, [extrema(x)...], [intercept + slope * x_end for x_end in extrema(x)];
               color = JL_RED, linewidth = style.linewidth)
        text!(ax, 0.03, 0.97; text = "R² = $(round(r2, digits = 3))", space = :relative, align = (:left, :top))
    end

    # Add title to the figure
    add_title!(fig, style, title)

    return fig
end


# Histograms of z-scored values, with the physical mean and std printed on every panel
#   - fields with per-layer stats (profiles) get one panel per layer, the others one panel
#   - works for column_io.fields with zscore.fields, and for fitted coefficients with e.g. zscore.linear
function plot_hist(
    data,                   # column_io.fields, or fitted coefficients
    stats,                  # matching z-score stats
    fields;                 # field(s) to show, e.g. :T or (:olw, :slwd)
    title = "",             # figure title
    style = (;),            # entries of hist_style() to change
)

    # Full style, and a single field as a one-element tuple
    style  = checked_merge(hist_style(), style)
    fields = fields isa Symbol ? (fields,) : fields

    # One (field, layer) per panel - k = nothing for a field with one mean and std
    panels   = [(field, k) for field in fields
                for k in (stats[field].mean isa AbstractVector ? eachindex(stats[field].mean) : (nothing,))]
    n_panels = length(panels)
    fig      = new_figure(style, n_panels; title)

    # One panel per (field, layer)
    for (i_panel, (field, k)) in enumerate(panels)

        # Mean and std of this layer, the values of this layer, and their z-scores
        μ, σ         = isnothing(k) ? (stats[field].mean, stats[field].std) : (stats[field].mean[k], stats[field].std[k])
        field_values = isnothing(k) ? data[field] : selectdim(data[field], 2, k)
        z_values     = filter(isfinite, vec(zscore(field_values, μ, σ)))

        # Define panel
        ax = panel(fig, style, i_panel, n_panels;
                   title = isnothing(k) ? probe_label(field) : "$(probe_label(field)) layer $(k)")

        # Draw histogram of zscores and display text
        hist!(ax, z_values; bins = style.bins, color = style.hist_color)
        text!(ax, 0.03, 0.97; text = "μ = $(round(μ, sigdigits = 4))\nσ = $(round(σ, sigdigits = 4))",
              space = :relative, align = (:left, :top))
    end

    # Add title to the figure
    add_title!(fig, style, title)

    return fig
end
