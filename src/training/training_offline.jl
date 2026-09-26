### Trains an emulator offline on a pre-generated target dataset
###
### Algorithm:
###
###     - Setup RNG
###     - Setup optimiser and load target data and split it into
###             - training set: used for training the emulator
###             - validation set: used for evaluating the emulator after every epoch
###     - Prepare logging/saving 
###
###     - Loop over epochs
###         - Shuffle the training samples
###         - Loop over batches
###             - Slice out training batch
###             - Compute gradients with Enzyme
###             - Compute and log metrics
###             - Update the optimiser and emulator
###
###         - Evaluate the validation loss and metrics and log
###         - Update learning rate
###
###     - Create plots after training





# Function for running an offline training
function training_offline(;
    spectral_grid,      # spectral_grid of the model (unused offline, kept for a uniform signature)
    emulator,           # longwave parameterization emulator to be trained
    tc,                 # run configuration (TrainConfigOffline)
)

    # Set seed for reproducibility
    Random.seed!(tc.seed)


    # Setup optimiser
    opt_state, eta = setup_optimiser(tc, ps=emulator.ps)


    # Load the target dataset, split into training and validation samples
    train_set, val_set = setup_target(tc, emulator)

    # Nr. of total training samples and nr. of batches per epoch
    n_train = size(train_set.X, 2)
    n_val = size(val_set.X, 2)
    n_batches = min(n_train ÷ tc.batchsize, tc.n_batches)


    # Initalize .csv files for logging
    metric_keys = keys(compute_metrics(
        residuals_offline(emulator.ps, offline_parts(emulator)..., take_batch(val_set, 1:1)),
        batch_config(tc.loss_config, take_batch(val_set, 1:1)),
        emulator, 
        make_zero(emulator.ps)
    ))
    csv_init((:epoch, :batch, :eta), metric_keys; dir=tc.dir, file="training.csv")
    csv_init((:epoch, :eta),         metric_keys; dir=tc.dir, file="validation.csv")

    # Initialize folder for training plots
    mkpath(joinpath(tc.dir, "train_plots"))


    # Print training config
    print_config(tc, n_train, n_val, n_batches)

    # Print training start information
    @info "Offline training started!"



    ### Main training loop
    # Loop over epochs
    for epoch in 1:tc.n_epochs

        # Shuffle the training samples, so a batch never sees one sample only
        perm = randperm(n_train)


        # Loop over batches
        for b in 1:n_batches

            # Slice out batch
            idx = view(perm, (b-1)*tc.batchsize + 1 : b*tc.batchsize)
            batch = take_batch(train_set, idx)


            # Print information of starting first training step
            if epoch == 1 && b == 1
                @info "Start 1st training step!"
            end


            # Compute gradients
            grads = compute_gradients(tc, emulator, batch)

            # Fail loudly: one NaN gradient turns every parameter into NaN permanently
            isfinite(tree_l2norm(grads)) || error("non-finite gradient at epoch $(epoch), batch $(b)")

            
            # Compute metrics and log to .csv file every 10th batch
            if b % 10 == 1

                metrics = compute_metrics(
                    residuals_offline(emulator.ps, offline_parts(emulator)..., batch),
                    batch_config(tc.loss_config, batch),
                    emulator,
                    grads
                )
                csv_row!((; epoch, batch=b, eta); metrics, dir=tc.dir, file="training.csv")
            end


            # Update optimiser and emulator
            opt_state, ps_new = Optimisers.update(opt_state, emulator.ps, grads)
            emulator = update_ps(emulator, ps_new)
        end


        # Evaluate on validation set (held-out trajectories)
        metrics_val = compute_metrics(
            residuals_offline(emulator.ps, offline_parts(emulator)..., val_set),
            batch_config(tc.loss_config, val_set),
            emulator,
            make_zero(emulator.ps)
        )
        csv_row!((; epoch, eta); metrics=metrics_val, dir=tc.dir, file="validation.csv")


        # Update learning rate after every epoch and update optimiser
        eta *= tc.eta_decay
        Optimisers.adjust!(opt_state, eta)


        # Print information
        @info "Epoch $(epoch) / $(tc.n_epochs) finished! val loss = $(metrics_val[:loss_total])"
    end
    
    # Log info
    @info "Training finished!"

    # Save training figures
    save_training_plots(tc; n_block=n_batches)


    # Return final trained emulator
    return emulator
end