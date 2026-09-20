### Trains a parameterization online in SpeedyWeather.jl
###
### Algorithm:
###     
###     - Setup RNG
###     - Setup optimiser and simulations
###             - template: sim used for copying before perturbation
###             - target:   sim used as target for gradient computation
###             - train:    sim of to be trained LW emulator
###     - Prepare logging/saving 
###     - Shuffle initial conditions (shuffling of starting seasons)
###
###     - Loop over initial conditions: n_ic
###         - Sample start date from shuffled initial conditions
###         - Prepare reference simulation sim_ref (copy, perturb and spinup)
###
###         - Loop over updates: n_updates
###
###             - Loop over gradient accumulation steps: n_accum
###                 - Copy sim_ref onto sim_target and sim_train
###                 - Compute gradients over a n_seg timesteps long trajectory
###                 - Accumulate gradient
###                 - Compute and log metrics
###                 - Propagagate sim_ref for n_seg + n_gap timesteps
###
###             - Calculate mean of accumulated gradients
###             - Update emulator and simulation after accumulation window
###
###         - Update learning rate
###
###     - Save training plots
###     - Return final trained emulator





# Function for running an online training
function training_online(;
    spectral_grid,      # spectral_grid of the model     
    emulator,           # longwave parameterization emulator to be trained
    tc,                 # run configuration (TrainConfigOnline)
)

    # Set seed for reproducibility
    Random.seed!(tc.seed)


    # Setup optimiser
    opt_state, eta = setup_optimiser(tc, ps=emulator.ps)

    # Setup simulations (template, training and target)
    sims = setup_simulations(spectral_grid, tc, emulator)


    # Initalize .csv file for logging
    metric_keys = keys(compute_metrics(
        residuals_online(sims.emulator.variables, sims.target.variables), 
        tc.loss_config, 
        emulator, 
        make_zero(emulator.ps))
    )
    csv_init((:ic, :update, :accum, :n_seg, :eta), metric_keys; dir=tc.dir, file="training.csv")

    # Initialize folder for training plots
    mkpath(joinpath(tc.dir, "train_plots"))


    # Shuffle ics
    bin_order = randperm(tc.n_ic)


    # Print training config
    print_config(tc, sims.template.model.time_stepping.Δt)

    if !tc.do_autodiff
        @warn "Autodiff is deactivated! Enzyme.autodiff is NOT used!"
    end

    # Print training start information
    @info "Online training started!"



    ### Main training loop
    ### Loop over initial conditions
    for ic in 1:tc.n_ic

        # Update number of steps used for calculating gradients
        n_seg = tc.n_seg_0 + (ic-1) * tc.n_seg_inc

        # Draw a starting date
        restart = pick_restart_state(tc.restart_scheme, tc.restart_unit, bin_order[ic], tc.n_ic, tc.restart_ics, tc.restart_js)
    
        # Prepare reference simulation (perturbation and spinup)
        sim_ref = prepare_reference(sims.template, tc, n_seg, restart)



        ### Loop over emulator updates
        for update in 1:tc.n_updates

            # Print information of starting first training update step
            if ic == 1 && update == 1
                @info "Start 1st training step!"
            end

            # Define gradient sum
            grad_sum = nothing
            


            ### Loop over gradient accumulation steps
            for accum in 1:tc.n_accum

                # Copy reference variables
                vars0 = deepcopy(sim_ref.variables) 

                # Set target variables to reference variables
                restart_from!(sims.target, vars0, n_seg)
                restart_from!(sims.emulator, vars0, n_seg)


                # Compute gradients
                grads = compute_gradients(tc, sims, vars0, n_seg)

                # Fail loudly: one NaN gradient turns every parameter into NaN permanently
                isfinite(tree_l2norm(grads)) || error("non-finite gradient at ic $(ic), update $(update), accum $(accum)")


                # Accumulate gradients over accumulation window
                grad_sum = isnothing(grad_sum) ? grads : tree_add(grad_sum, grads)


                # Compute metrics for logging
                metrics = compute_metrics(
                    residuals_online(sims.emulator.variables, sims.target.variables),
                    tc.loss_config,
                    emulator,
                    grads
                )
                csv_row!((; ic, update, accum, n_seg, eta); metrics, dir=tc.dir, file="training.csv")


                # Propagate reference trajectory forward
                sim_timesteps!(sim_ref, n_seg+tc.n_gap)
            end


            ### Update emulator after accumulation window
            # Calculate mean
            grad_mean = tree_scale(grad_sum, 1f0/tc.n_accum)

            # Update optimiser and emulator
            opt_state, ps_new = Optimisers.update(opt_state, emulator.ps, grad_mean)
            emulator = update_ps(emulator, ps_new)

            # Update training simulation
            sims = @set sims.emulator.model.longwave_radiation = emulator
        end


        # Update learning rate after every ic and update optimiser
        eta *= tc.eta_decay
        Optimisers.adjust!(opt_state, eta)


        @info "Initial condition $(ic) / $(tc.n_ic) finished!"
    end

    # Log info
    @info "Training finished!"

    # Save training figures
    save_training_plots(tc; n_block=tc.n_accum)

    
    # Return final trained emulator
    return emulator
end