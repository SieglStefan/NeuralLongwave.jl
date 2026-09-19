### Loss computation
###
### Functions for defining the loss function, seeding loss (AD) and defining loss configs
###         - 1) Loss definition and computation
###         - 2) Loss configuration struct and constructors
###         - 3) Offline training loss and residuals
###         - 4) Online training loss and residuals










### 1) Loss definition and computation

# Loss function for computing the total weighted MSE of residuals
@generated function loss(res::NamedTuple{names}, lc) where {names}

    # One term per residual field
    terms = [:(lc.loss_weights.$f * field_mse(res.$f, lc.norm_weights.$f, lc.area_weights)) for f in names]

    # Generates for example:
    #   lc.loss_weights.olw  * field_mse(res.olw,  lc.norm_weights.olw,  lc.area_weights) +
    #   lc.loss_weights.slwd * field_mse(res.slwd, lc.norm_weights.slwd, lc.area_weights) +
    #   lc.loss_weights.dT   * field_mse(res.dT,   lc.norm_weights.dT,   lc.area_weights)
    return Expr(:call, :+, terms...)
end

            








### 2) Loss configuration struct and constructors

# Struct holding loss configuration parameters
struct LossConfig{W<:NamedTuple, F<:NamedTuple, G}
    loss_weights::W         # loss weighting factors
    norm_weights::F         # field normalization factors (zscore)
    area_weights::G         # grid area weights
end


# Convenvience constructor for LossConfig for online training
function LossConfig(;
    spectral_grid::SpectralGrid,        # spectral grid
    zscore_scheme::String,              # name of the zscore model
    zscore_unit::String,                # name of the zscore unit
    n_seg_0::Int,                       # length of the initial differentiation segment (in timesteps)    
    dt_sec::Real,                       # length of a timestep in seconds
    loss_weights::NamedTuple,           # weights of the loss terms, e.g. (; T = 1f0, olw = 1f0, slwd = 1f0)
)

    # Load normalization weights
    nw_zscore = zscore_norm_weights(zscore_scheme, zscore_unit)

    # Calculate segment length in seconds
    t_seg = Float32(n_seg_0 * dt_sec)

    # Define normalization weights and reshape T and dT to (1, nlayers) for loss broadcasting
    norm_weights = (;
        T    = reshape(nw_zscore.dT .* t_seg, 1, :),        # reshape to (1, nlayers)
        olw  = nw_zscore.olw,                               # keep scalar
        slwd = nw_zscore.slwd,                              # keep scalar    
        dT   = reshape(nw_zscore.dT, 1, :)                  # reshape to (1, nlayers)
    )

    return LossConfig(loss_weights, norm_weights, area_weights(spectral_grid))
end


# Convenvience constructor for LossConfig for offline training
function LossConfigOffline(;
    zscore_scheme::String,
    zscore_unit::String,
    loss_weights::NamedTuple,           # weights of the loss terms, e.g. (; olw = 1f0, slwd = 1f0, dT = 1f0)
)

    # No reshape as in online loss needed, because zscore_norm_weights already in (nlayers,) format
    return LossConfig(loss_weights, zscore_norm_weights(zscore_scheme, zscore_unit), nothing)
end

# Loss config carrying the per-sample area weights of an offline batch
batch_config(lc, batch) = LossConfig(lc.loss_weights, lc.norm_weights, batch.aw)



# Load zscore normalization factors of the loss function
function zscore_norm_weights(zscore_scheme::String, zscore_unit::String)

    # Load zscore stats data and extract number of vertical layers
    data = load(; dir=zscore_dir(zscore_scheme, zscore_unit), file="zscore.jld2")

    return (;
        olw  = Float32(data.fields.olw.std[1]),         # scalar
        slwd = Float32(data.fields.slwd.std[1]),        # scalar
        dT   = Float32.(data.fields.dT.std),            # (nlayers,)
    )
end










### 3) Offline training loss and residuals

# Loss wrapper for computing gradients for offline training
function loss_offline(ps, nn, st, zs, output_form, batch, lc) 

    # Return loss
    return loss(residuals_offline(ps, nn, st, zs, output_form, batch), lc)
end

# Residuals of an offline batch, from the decoded scheme outputs
function residuals_offline(ps, nn, st, zs, output_form, batch)

    # Compute scheme output
    Y = apply_offline(ps, nn, st, batch.X)
    Y = inv_zscore(Y, zs.output_mean, zs.output_std)
    out = decode(output_form, Y, batch.T_prof, batch.center)

    # Return residuals in form (nlayers, N)
    return (;
        olw  = reshape(out.olw  .- batch.olw,  1, :),
        slwd = reshape(out.slwd .- batch.slwd, 1, :),
        dT   = out.dT .- batch.dT,
    )
end










### 4) Online training loss and residuals

# Loss wrapper for computing gradients for online training
function loss_online(vars_emulator, vars_target, lc)

    # Return loss
    return loss(residuals_online(vars_emulator, vars_target), lc)
end

# Residuals of an online training step, taken from the two simulations
function residuals_online(vars_emulator, vars_target)

    # Define extracting functions
    T(v)    = SpeedyWeather.get_step(v.grid.temperature)
    olw(v)  = v.parameterizations.outgoing_longwave
    slwd(v) = v.parameterizations.surface_longwave_down

    # Return residuals in form (npoints, nlayers)
    return (; 
        T    = T(vars_emulator)    .- T(vars_target),         
        olw  = olw(vars_emulator)  .- olw(vars_target),
        slwd = slwd(vars_emulator) .- slwd(vars_target),
    )
end



# Loss seeding for AD
function seed_loss(tc, sims, vars_ad)

    # Create empty gradient container for autodiff
    bvars_ad = make_zero(vars_ad)


    # Extract final emulator and target fields
    T_emulator      = SpeedyWeather.get_step(sims.emulator.variables.grid.temperature)
    T_target        = SpeedyWeather.get_step(sims.target.variables.grid.temperature)

    olw_emulator    = sims.emulator.variables.parameterizations.outgoing_longwave
    olw_target      = sims.target.variables.parameterizations.outgoing_longwave

    slwd_emulator   = sims.emulator.variables.parameterizations.surface_longwave_down
    slwd_target     = sims.target.variables.parameterizations.surface_longwave_down


    # Unpack loss weighting, field normalization and area weights
    (; loss_weights, norm_weights, area_weights) = tc.loss_config


    # Seed the gradient containers with dL/d(output), evaluated at the state after n_seg steps
    SpeedyWeather.get_step(bvars_ad.grid.temperature) .=
        loss_weights.T .* 2f0 .* area_weights .* (T_emulator .- T_target) ./ norm_weights.T.^2 ./ length(T_emulator)

    bvars_ad.parameterizations.outgoing_longwave .=
        loss_weights.olw .* 2f0 .* area_weights .* (olw_emulator .- olw_target) ./ norm_weights.olw.^2 ./ length(olw_emulator)

    bvars_ad.parameterizations.surface_longwave_down .=
        loss_weights.slwd .* 2f0 .* area_weights .* (slwd_emulator .- slwd_target) ./ norm_weights.slwd.^2 ./ length(slwd_emulator)


    return bvars_ad
end