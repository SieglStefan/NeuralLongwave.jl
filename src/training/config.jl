### Training Configuration structs
###
### Structs for holding the training configuration parameters for offline and online training
###
### No field has a default: every value is set in scripts/training/defaults.jl (one place only)





# Struct holding offline training parameters (other parameters defined in the target data, generated from derive_column_io())
@kwdef struct TrainConfigOffline
    unit::String                        # name of the training run
    dir::String                         # directory for storing training runs
    seed::Int                           # seed for RNG

    target_scheme::String               # scheme of the target dataset
    target_unit::String                 # name of the target dataset unit

    target_ics::AbstractVector{Int}     # slice of ICs of pre-generated column IO data to use for training and validation
    n_ic_val::Int                       # number of ICs used for validation (rest for training)

    eta0::Float32                       # initial learning rate
    eta_decay::Float32                  # learning rate decay after each epoch
    clip_norm::Float32                  # clip norm for gradients
    weight_decay::Float32               # weight decay for parameters
    loss_config::LossConfig             # weighting and normalization of the loss

    n_epochs::Int                       # number of epochs for training
    n_batches::Int                      # number of batches per epoch
    batchsize::Int                      # training batch size (number of samples per update)
end



# Struct holding online training parameters
@kwdef struct TrainConfigOnline
    unit::String                        # name of the training run
    dir::String                         # directory for storing training runs
    seed::Int                           # seed for RNG

    model::Type                         # model used for training
    target::SpeedyWeather.AbstractLongwave      # target LW scheme

    restart_scheme::String              # scheme of the restart state data
    restart_unit::String                # name of the restart state data
    restart_ics::AbstractVector{Int}    # slice of restart initial conditions to use
    restart_js::AbstractVector{Int}     # slice of restart states to use

    eta0::Float32                       # initial learning rate
    eta_decay::Float32                  # learning rate decay after an ic
    clip_norm::Float32                  # clip norm for gradients
    weight_decay::Float32               # weight decay for parameters
    loss_config::LossConfig             # weighting and normalization of the loss

    t_spinup::Period                    # spinup time before training

    n_ic::Int                           # nr. of ic used for training
    n_updates::Int                      # nr. of scheme updates per ic
    n_accum::Int                        # nr. of trajectory gradients accumulated per update
    n_seg_0::Int                        # nr. of steps of initial differentiation segment
    n_seg_inc::Int                      # increase of differentiation segment
    n_gap::Int                          # nr. of timesteps between differentiation segments (for decorrelation of gradients)

    fac_pert_T::Float32                 # additive perturbation factor for temperature
    fac_pert_q::Float32                 # multiplicative perturbation factor for humidity

    do_autodiff::Bool                   # whether to use autodiff for training
end
