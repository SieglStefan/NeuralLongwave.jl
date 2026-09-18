### Gradient computation
###
### Calculate online and offline gradients using Enzyme.jl
###         - 1) Offline gradient
###         - 2) Online gradient










### 1) Offline gradient

# Gradient of the offline batch loss
function compute_gradients(tc::TrainConfigOffline, emulator, batch)

    # Container for the parameter gradients
    bps = make_zero(emulator.ps)

    # Scheme pieces that are held constant (ps is the only differentiated argument)
    nn, st, zs, of = offline_parts(emulator)

    # Differentiate the batch loss w.r.t. the scheme parameters
    Enzyme.autodiff(
        Enzyme.Reverse, loss_offline, Enzyme.Active,
        Duplicated(emulator.ps, bps),
        Const(nn), Const(st), Const(zs), Const(of),
        Const(batch), Const(batch_config(tc.loss_config, batch)),
    )

    return bps
end










### 2) Online gradient

# XXX Gradient computation wrapper allowing do_autodiff=false testmode
function compute_gradients(tc::TrainConfigOnline, sims, vars0, n_seg)

    # Test mode: return zero gradients, without Enzyme ever being reached
    if !tc.do_autodiff
        return make_zero(sims.emulator.model.longwave_radiation.ps)
    end

    # Normal mode: call Enzyme.autodiff
    return Base.invokelatest(autodiff_gradients, tc, sims, vars0, n_seg)
end


# XXX Gradient computation over a n_steps trajectory using Enzyme
@noinline function autodiff_gradients(tc, sims, vars0, n_seg)

    # Create adjoint vars from reference variables vars0
    vars_ad = deepcopy(sims.emulator.variables)
    copy!(vars_ad, vars0)

    # Calculate loss and seed AD with dL/dT
    bvars_ad = seed_loss(tc, sims, vars_ad)


    # Copy emulator model and seed model gradient container with zeros
    model_ad = deepcopy(sims.emulator.model)
    bmodel_ad = make_zero(model_ad)


    # Checkpointing avoids storing the full forward trajectory in memory
    checkpoint_scheme = Revolve(n_seg)

    # Differentiate n_steps of timestep! in reverse mode.
    Enzyme.autodiff(
        Enzyme.Reverse, checkpointed_timesteps!, Const,
        Duplicated(vars_ad, bvars_ad),
        Duplicated(model_ad, bmodel_ad),
        Const(n_seg), Const(checkpoint_scheme),
    )

    # Extract parameter gradients from bmodel_ad
    grads = bmodel_ad.longwave_radiation.ps

    return grads
end


# Perform several timestep! calls with checkpointing for reverse-mode AD
function checkpointed_timesteps!(
    vars_ad,
    model_ad,
    n_steps,
    checkpoint_scheme::Scheme,
)

    # Perform n_steps of time_step! with checkpointing for reverse-mode AD
    @ad_checkpoint checkpoint_scheme for _ in 1:n_steps
        SpeedyWeather.time_step!(vars_ad, model_ad.time_stepping, model_ad)             # propagate dynamics
        SpeedyWeather.time_step!(vars_ad.prognostic.clock, model_ad.time_stepping)      # propagate clock
    end

    return nothing
end