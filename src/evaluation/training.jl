### Training evaluation
###
### Curves of the logged training metrics (training.csv, validation.csv), several runs at once.
###         - 1) Helpers
###         - 2) Plotting
###         - 3) Saving
###         - 4) Series summary
###
### Fixed metrics:
###     - plot_training:        loss_total (+ validation, offline only), pnorm, gnorm
###     - plot_loss_shares:     share of every field in the loss: lambda_f * loss_f / loss_total
###     - plot_rmse:            rmse per field, in physical units










### 1) Helpers

# Calculates mean over block of n_block rows, placed at the last row of each block
#   - samples is one metric column of the training log, e.g. run.train.loss_total
function block_mean(samples, n_block)

    # Define starting and matching end rows
    #   - e.g.: first_rows = [1, 11, 21, 31,...], last_rows = [10, 20, 30, 40,...]
    first_rows = 1:n_block:length(samples)
    last_rows  = [min(first_row + n_block - 1, length(samples)) for first_row in first_rows]

    # Calculate and return row block means of samples
    return last_rows, [Float64(mean(view(samples, first_row:last_row))) for (first_row, last_row) in zip(first_rows, last_rows)]
end


# Calculates x-positions where a block ends for vertical separation lines
#   - train is a loaded run.train from a loaded train.csv (load_run())
function block_ends(train)

    # Block of every row: the IC online, the epoch offline
    blocks = hasproperty(train, :ic) ? train.ic : train.epoch

    # Return x-positions of in between blocks (between blocks = blocks[row] != blocks[row+1])
    return [row + 0.5 for row in 1:length(blocks)-1 if blocks[row] != blocks[row+1]]
end


# Calculates x-values for validation data (padding values)
#   - e.g. train.epoch = [1,1,1,2,2,2,3,3,3] but val.epoch = [1,2,3] -> val_rows = [3,6,9]
val_rows(train, val) = [findlast(==(epoch), train.epoch) for epoch in val.epoch]



# RMSE label and scaling of dT or T
#   - dT not included in PROBES, therefore special treatment
rmse_label(field) = field === :dT ? "RMSE dT [K/day]" : axis_label(:rmse, field)
rmse_scale(field) = field === :dT ? 86400 : 1










### 2) Plotting

# Loss, parameter norm and gradient norm of several runs, one line per run
#   - n_block > 1 draws the raw loss faintly and its block mean on top
#   (online: n_accum, offline: n_batches)
function plot_training(
    runs;                   # training runs (collect_runs()), keyed by unit
    n_block = 1,            # rows per block of the loss mean
    looks   = nothing,      # appearance per unit
    title   = "",           # figure title
    style   = (;),          # entries of training_style() to change
)

    # Full style and figure, offline runs add one legend entry for the validation lines
    style     = checked_merge(training_style(), style)
    has_val   = any(run -> !isnothing(run.val), values(runs))
    n_entries = n_legend_entries(looks, keys(runs)) + has_val
    fig       = new_figure(style, 3; title, n_entries)


    # One panel per metrics
    panel_ax = map(enumerate((:loss_total, :pnorm, :gnorm))) do (i_panel, metric)

        # Pnorm barely moves: gets a linear axis
        yscale = metric === :pnorm ? identity : log10

        # Define panel
        ax = panel(fig, style, i_panel, 3; xlabel = "training step", ylabel = string(metric), yscale)


        # One line per run
        for (i_unit, (unit, run)) in enumerate(pairs(runs))

            # Merge looks and extract values of current loop metric
            look = look_of(looks, unit, i_unit, style)
            metric_values = yscale === identity ? Float64.(run.train[!, metric]) : positive(run.train[!, metric])

            # Loss: raw faintly, block mean on top (only if n_block>1, else draw raw normal)
            if metric === :loss_total && n_block > 1
                lines!(ax, metric_values; color = (look.color, style.raw_alpha), linewidth = style.linewidth / 2)
                lines!(ax, block_mean(metric_values, n_block)...; color = look.color, linestyle = look.linestyle,
                       linewidth = style.linewidth, label = look.label)
            else
                lines!(ax, metric_values; color = look.color, linestyle = look.linestyle,
                       linewidth = style.linewidth, label = look.label)
            end

            # Validation loss, one marker per epoch (offline only)
            if metric === :loss_total && !isnothing(run.val)
                scatterlines!(ax, val_rows(run.train, run.val), positive(run.val.loss_total);
                              color = look.color, linestyle = :dash, linewidth = style.linewidth, markersize = 4)
            end
        end

        # One legend entry explaining the dashed validation lines
        if metric === :loss_total && has_val
            scatterlines!(ax, [NaN], [NaN]; color = :black, linestyle = :dash, markersize = 4, label = "validation")
        end

        # Block ends of the first run, the runs of one series share them
        vlines!(ax, block_ends(first(values(runs)).train); color = :gray, linestyle = :dot, linewidth = style.linewidth / 2)

        return ax
    end

    # Add legend and title to the figure
    add_legend!(fig, first(panel_ax), style, 3, n_entries)
    add_title!(fig, style, title)

    return fig
end



# Share of every weighted field in the loss of ONE run (shares sum to 1)
function plot_loss_shares(
    run;                    # one training run (load_run)
    weights,                # loss weights of the run, fields with weight 0 are left out
    title = "",             # figure title
    style = (;),            # entries of shares_style() to change
)

    # Full style, the weighted fields the run logged, and the figure
    style  = checked_merge(shares_style(), style)
    fields = [field for field in keys(weights) if weights[field] > 0 && hasproperty(run.train, Symbol(:loss_, field))]
    fig    = new_figure(style, 1; title, n_entries = length(fields))
    ax     = panel(fig, style, 1, 1; xlabel = "training step", ylabel = "loss share", limits = (nothing, (0, 1)))


    # One line per field
    for field in fields
        lines!(ax, weights[field] .* run.train[!, Symbol(:loss_, field)] ./ run.train.loss_total;
               color = FIELD_COLORS[field], linewidth = style.linewidth, label = probe_label(field))
    end

    # Draw block separations
    vlines!(ax, block_ends(run.train); color = :gray, linestyle = :dot, linewidth = style.linewidth / 2)

    # Add legend and title to the figure
    add_legend!(fig, ax, style, 1, length(fields))
    add_title!(fig, style, title)

    return fig
end



# RMSE of every logged field, one panel per field, one line per run
#   - offline runs log no T -> no T panel
#   - online runs log no dT -> no dT panel
function plot_rmse(
    runs;                   # training runs (collect_runs), keyed by unit
    looks = nothing,        # appearance per unit
    title = "",             # figure title
    style = (;),            # entries of rmse_style() to change
)

    # Full style, the fields at least one run logged, and the figure
    style     = checked_merge(rmse_style(), style)
    fields    = [field for field in (:T, :olw, :slwd, :dT)
                 if any(run -> hasproperty(run.train, Symbol(:rmse_, field)), values(runs))]
    n_panels  = length(fields)
    n_entries = n_legend_entries(looks, keys(runs))
    fig       = new_figure(style, n_panels; title, n_entries)


    # One panel per field
    panel_ax = map(enumerate(fields)) do (i_panel, field)

        # Define panel
        ax = panel(fig, style, i_panel, n_panels; xlabel = "training step", ylabel = rmse_label(field))

        # One line per run that logged this field
        for (i_unit, (unit, run)) in enumerate(pairs(runs))

            # Skip runs that did not log this field
            hasproperty(run.train, Symbol(:rmse_, field)) || continue

            # Merge looks and draw line of current loop run
            look = look_of(looks, unit, i_unit, style)
            lines!(ax, run.train[!, Symbol(:rmse_, field)] .* rmse_scale(field);
                   color = look.color, linestyle = look.linestyle, linewidth = style.linewidth, label = look.label)
        end

        # Block ends of the first run, the runs of one series share them
        vlines!(ax, block_ends(first(values(runs)).train); color = :gray, linestyle = :dot, linewidth = style.linewidth / 2)

        return ax
    end

    # Add legend and title to the figure
    add_legend!(fig, first(panel_ax), style, n_panels, n_entries)
    add_title!(fig, style, title)

    return fig
end










### 3) Saving

# Wrapper for saving standard figures of one finished training run
function save_training_plots(tc; n_block = 1)

    # Load run from tc.dir and define saving directory
    run  = load_run(tc.dir)
    dir  = joinpath(tc.dir, "train_plots")

    # Create NamedTuple (; unit = run), because plot_rmse() and plot_training() expect a NamedTuple
    runs = (; Symbol(tc.unit) => run)

    # Save standard figures
    save_figure(plot_training(runs; n_block), joinpath(dir, "training.png"))
    save_figure(plot_loss_shares(run; weights = tc.loss_config.loss_weights), joinpath(dir, "loss_shares.png"))
    save_figure(plot_rmse(runs), joinpath(dir, "rmse.png"))

    # Log info
    @info "Training plots written to $(dir)!"

    return nothing
end










### 4) Series summary

# One row per offline unit of a training series, best first
#   - offline only:     it reads validation.csv, which only offline runs write
#   - by:               metric after units are ranked
#   - settled:          epoch after which the improvement stayed below tol
#   - converged:        true if a whole window before last n_ep stayed flat (inside tol)
#   - pct:              how far a unit sits above the best one, in %
function summarize_series(experiment, series; by = :loss_total, n_ep = 10, tol = 0.03)

    # Collect finished offline training runs
    units = filter(unit -> isfile(joinpath(emulator_dir(experiment, series, unit), "validation.csv")),
                   sort(readdir(joinpath(ROOT, "results", experiment, series))))

    # Throw error if no unit of the series was trained offline
    isempty(units) && error("no unit of $(experiment)/$(series) has a validation.csv - summarize_series is offline only")


    # Create table
    table = DataFrame(map(units) do unit

        # Extract validation metric and compute settled epoch
        val_metric = csv_read(; dir = emulator_dir(experiment, series, unit), file = "validation.csv")[!, by]
        settled = epoch_settled(val_metric, n_ep, tol)

        # Return row data
        (; unit,
           final       = Float64(mean(val_metric[end-n_ep+1:end])),
           settled,
           # Only count as converged if the curve has stayed flat for at least one full window before the end
           converged   = length(val_metric) - settled + 1 >= n_ep)      
    end)

    # Best first, the rest in % above it
    sort!(table, :final)
    table.pct = round.(100 .* (table.final ./ table.final[1] .- 1); digits = 1)

    # Rename final column to the validation metric
    return rename!(table, :final => by)
end


# Epoch from which the validation metric stayed within tol of its final mean value
function epoch_settled(val_metric, n_ep, tol)

    # Final mean value of the run
    final = mean(val_metric[end-n_ep+1:end])

    # Walk back from the last epoch while the epochs before is still within tol of the final value (sliding mean window)
    settled = length(val_metric)
    while settled > n_ep && abs(mean(val_metric[settled-n_ep:settled-1]) /final - 1) <= tol
        settled -= 1
    end

    return settled
end
