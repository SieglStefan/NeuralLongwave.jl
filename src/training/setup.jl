### Setup functions
###
### Functions for setting up and preparing simulations and optimisers for training
###         - 1) General
###         - 2) Offline Training
###         - 3) Online Training  










### 1) General

# Setup optimiser for training loop
function setup_optimiser(tc; ps)

    # Copy learning rate
    eta = tc.eta0

    # Setup Optimiser rule
    rule = Optimisers.OptimiserChain(
        Optimisers.ClipNorm(tc.clip_norm),              # ClipNorm for stability (limits gradients)
        Optimisers.WeightDecay(tc.weight_decay),        # WeightDecay for stability (limits parameters)
        Optimisers.Adam(eta),                           # Adam optimiser with learning rate eta
    )

    # Define optimiser state
    opt_state = Optimisers.setup(rule, ps)

    return opt_state, eta
end










### 2) Offline Training

# Sets up training and validation sets from the target dataset for offline training
function setup_target(tc, emulator)

    # Put together dataset filepath
    dir = column_io_dir(tc.target_scheme, tc.target_unit)
    file = "column_io.jld2"

    # Throw a helpful error if the dataset was never generated
    isfile(joinpath(dir, file)) || error(
        "No column_io dataset at $(joinpath(dir, file)). Generate it with:\n" *
        "    derive_column_io(; raw_dir = ..., scheme = \"$(tc.target_scheme)\", unit = \"$(tc.target_unit)\", ic_subset = ...)")

    # Load stored target dataset and unpack the fields and the stored ics
    data = load(; dir, file)
    (; fields, ic_subset, spectral_grid, model_type) = data


    # Every requested IC has to be present in the stored dataset
    absent = setdiff(tc.target_ics, ic_subset)
    isempty(absent) || error("column_io dataset holds ICs $(ic_subset), unit requests $(collect(tc.target_ics)) - missing $(absent)!")

    # Extract number of states per IC and throw error if it is not equal among ICs
    n_states_per_ic, rest = divrem(size(fields.T, 3), length(ic_subset))
    rest == 0 || error("Target dataset has $(size(fields.T,3)) states over $(length(ic_subset)) ICs - not equally sized!")


    # Collect consts
    model = model_type(spectral_grid)
    consts = (; center = emulator.zscore.center, flux_to_dT = flux_to_dT_fac(model))


    # Sample indices one stored IC occupies (for example 1:100 for ic 1, 101:200 for ic 2, etc.)
    block(ic) = (findfirst(==(ic), ic_subset) - 1) * n_states_per_ic .+ (1:n_states_per_ic)

    # Split the requested ICs, validation holding out whole ICs (never single samples)
    1 <= tc.n_ic_val < length(tc.target_ics) ||
        error("n_ic_val = $(tc.n_ic_val) leaves none of the $(length(tc.target_ics)) requested ICs for training!")
    ics_train = collect(tc.target_ics)[1 : end - tc.n_ic_val]
    ics_val   = collect(tc.target_ics)[end - tc.n_ic_val + 1 : end]

    # Concatenate the sample blocks of each side
    range_train = reduce(vcat, block.(ics_train); init = Int[])
    range_val   = reduce(vcat, block.(ics_val);   init = Int[])

    # Extract training and validation sets
    aw = area_weights(spectral_grid)
    train_set = extract_set(fields, emulator, range_train, aw, consts)
    val_set   = extract_set(fields, emulator, range_val, aw, consts)

    return train_set, val_set
end


# Extracts and formats set of states from the target fields 
function extract_set(fields, emulator, range, aw, consts)

    # Flatten a profile (npoints, nlayers, n_samples_total) -> (nlayers, npoints*n_samples_total), a scalar -> (1, npoints*n_samples_total)
    #   (from generate_target format (SW) -> Lux standard format)
    flat_prof(A) = reshape(permutedims(A[:, :, range], (2,1,3)), size(A, 2), :)
    flat_scal(A) = reshape(A[:, range], 1, :)


    # Merge together input fields to input vector X and zscore transform (ConstLW has no inputs)
    n_samples = size(fields.T, 1) * length(range)
    X = reduce(vcat, (INPUTS[k].kind === :profile ? flat_prof(fields[k]) : flat_scal(fields[k])
                        for k in keys(emulator_inputs(emulator)));
               init = zeros(Float32, 0, n_samples))
    X = zscore(X, emulator.zscore.input_mean, emulator.zscore.input_std)

    
    # Put together column
    col = (; 
        T_prof  = flat_prof(fields.T),
        olw     = vec(flat_scal(fields.olw)),
        slwd    = vec(flat_scal(fields.slwd)),
        dT      = flat_prof(fields.dT),
        ps      = vec(flat_scal(fields.p)),
        slwu    = vec(flat_scal(fields.slwu)),  
    )


    # Return input and targets
    return (;
        X,
        col,
        consts,
        aw = reshape(repeat(aw, length(range)), 1, :)
    )
end


# Slice samples from of a set indicated by the index range
function take_batch(set, idx)
    return (;
        X      = set.X[:, idx],
        col    = (; T_prof = set.col.T_prof[:, idx], 
                    dT = set.col.dT[:, idx],
                    olw = set.col.olw[idx], slwd = set.col.slwd[idx],
                    ps  = set.col.ps[idx],  slwu = set.col.slwu[idx]
                ),
        consts = set.consts,
        aw     = set.aw[:, idx],
    )
end











### 3) Online Training

# Setup simulations for online training loop
function setup_simulations(spectral_grid, tc, emulator)

    # Create template model and simulation for later copying
    model_template  = tc.model(spectral_grid; longwave_radiation = tc.target)
    sim_template    = spinup_leapfrog!(initialize!(model_template))

    # Create target simulation as training target
    model_target    = tc.model(spectral_grid; longwave_radiation = tc.target)
    sim_target      = spinup_leapfrog!(initialize!(model_target))

    # Create training simulation (to be trained scheme)
    model_emulator     = tc.model(spectral_grid; longwave_radiation = emulator)
    sim_emulator       = spinup_leapfrog!(initialize!(model_emulator))

    return (; template = sim_template, target = sim_target, emulator = sim_emulator,)
end



# Prepare reference simulation (copying, perturbation, spinup)
function prepare_reference(sim_template, tc, n_seg, restart)

    # Copy template simulation for pertubation and set start date
    sim_pert = deepcopy(sim_template)
    restart_from!(sim_pert, restart, 0)

    # Perturb temperature and humidity fields
    perturb_grid_field!(sim_pert, :temperature; fac_add = tc.fac_pert_T)
    perturb_grid_field!(sim_pert, :humidity; fac_mult = tc.fac_pert_q, zeromin = true)
        
    # Spinup simulation 
    run!(sim_pert, period = tc.t_spinup)

    # Create reference simulation
    sim_ref = deepcopy(sim_pert)

    # Initialize reference trajectory and do first steps
    steps = tc.n_updates * tc.n_accum * (tc.n_gap + n_seg)
    spinup_leapfrog!(sim_ref, total_steps=steps)

    return sim_ref
end



# Samples starting dates uniformly across a year
function pick_restart_state(restart_scheme, restart_unit, ic, n_ic, restart_ics, restart_js)
    
    # Cycle the restart ICs, the caller already passes a shuffled ic
    restart_ic = restart_ics[mod1(ic, length(restart_ics))]

    # Spread the n_ic training ICs evenly over the available restart seasons
    j = restart_js[mod1(floor(Int, (ic - 1) * length(restart_js) / n_ic) + 1, length(restart_js))]

    # Return sampled day
    return restart_state(restart_scheme, restart_unit, restart_ic, j)
end