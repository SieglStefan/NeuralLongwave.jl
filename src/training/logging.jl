### Logging of training data
###
### Functions for computing training data (.csv) and printing training configs
###         - 1) .csv metrics computation
###         - 2) Configuration printing










### 1) .csv metrics computation

# Function for computing metrics (losses, rmse, pnorm, gnorm) during training
function compute_metrics(res, lc, lw_scheme, grads)

    # Unweighted loss per field — its share in a plot is lambda_f * loss_f / loss_total
    losses = (; (Symbol(:loss_, f) => field_mse(res[f], lc.norm_weights[f], lc.area_weights)
                 for f in keys(res))...)

    # Raw rmse per field, in physical units (K, W/m^2, K/s) — the number you can quote
    rmses  = (; (Symbol(:rmse_, f) => sqrt(field_mse(res[f], 1f0, lc.area_weights))
                 for f in keys(res))...)

    return (;
        loss_total = loss(res, lc),
        losses...,
        rmses...,

        # Optimizer diagnostics
        pnorm = tree_l2norm(lw_scheme.ps),
        gnorm = tree_l2norm(grads),
    )
end







 


### 2) Configuration printing

# Print information about the offline training run configuration
function print_config(tc::TrainConfigOffline, n_train, n_val, n_batches)

    # Print info
    println("----------Offline training configuration:----------")
    println("  - Target dataset: ", tc.target_scheme, "_", tc.target_unit)
    println("  - Total samples (atmospheric columns): \t", n_train+n_val, "\t(", n_train, " training\t", n_val, " validation)")
    println("  - Used per epoch: \t", n_batches * tc.batchsize,
            "\t(", round(100 * n_batches * tc.batchsize / n_train, digits = 1), "% of the training set)")
    println("  - Total updates: ", n_batches * tc.n_epochs,
            "\t(", n_batches, " per epoch, ", tc.batchsize, " columns each)")
    println("  - Learning rate budget: ", eta_budget(tc.eta0, tc.eta_decay, tc.n_epochs, n_batches))
    println("---------------------------------------------------")

    return nothing
end


# Print information about the online training run configuration
function print_config(tc::TrainConfigOnline, dt_sec)

    # Single time step in days
    dt_day = dt_sec /3600 /24

    # Gradients per ic and total updates
    up_total = tc.n_ic * tc.n_updates

    # Length of one gradient segment, first and last ic
    t_seg_start = tc.n_seg_0 * dt_day
    t_seg_end   = (tc.n_seg_0 + tc.n_seg_inc * (tc.n_ic - 1)) * dt_day

    # Simulated time per ic
    t_ic_start = tc.n_updates * tc.n_accum * (t_seg_start + tc.n_gap * dt_day)
    t_ic_end   = tc.n_updates * tc.n_accum * (t_seg_end   + tc.n_gap * dt_day)

    # Print info
    println("----------Online training configuration:----------")
    println("  - Total updates: ", up_total, "\t(", tc.n_updates, " per ic, ", tc.n_accum, " gradients each)")
    println("  - Learning rate budget: ", eta_budget(tc.eta0, tc.eta_decay, tc.n_ic, tc.n_updates))
    println("  - Segment length (hours): \t\tStart: ", t_seg_start*24, "\tEnd: ", t_seg_end*24)
    println("  - Simulated time per ic (days): \tStart: ", t_ic_start,  "\tEnd: ", t_ic_end)
    println("  - Total simulated time (days): ", tc.n_ic * (t_ic_start + t_ic_end) / 2)
    println("--------------------------------------------------")

    return nothing
end


# Total learning rate budget: sum of eta over every update (how far Adam can move parameters in total)
eta_budget(eta0, decay, n_stages, updates_per_stage) =
    eta0 * updates_per_stage * (decay ≈ 1f0 ? n_stages : (1f0 - decay^n_stages) / (1f0 - decay))