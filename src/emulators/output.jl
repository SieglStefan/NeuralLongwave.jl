### Output handling
###
### Utilities for decoding output vectors and writing tendencies and fluxes
###         - 1) Helper functions
###         - 2) Decoding: Mutating single columns
###         - 3) Decoding: Mutating multiple columns
###         - 4) Temperature tendency and flux writing










### 1) Helper functions

# Mid layer index of a vertical profile
mid_layer(nlayers) = nlayers ÷ 2


# Define output form struct for parameterizations
struct DirectOutput end
struct LinearOutput end
struct PlanckOutput end
struct FluxOutput end

# Utility functions for ouput forms
output_group(::DirectOutput) = :fields
output_group(::LinearOutput) = :linear
output_group(::PlanckOutput) = :planck
output_group(::FluxOutput)   = :fields

# Utility functions for output keys
output_keys(::DirectOutput) = (:dT, :olw, :slwd)
output_keys(::LinearOutput) = (:t1, :t2, :o1, :o2, :o3, :s1, :s2, :s3)
output_keys(::PlanckOutput) = (:t1, :t2, :o1, :o2, :o3, :s1, :s2, :s3)
output_keys(::FluxOutput)   = (:F, )

# Predictor function for output forms
pred(::DirectOutput, x) = nothing
pred(::LinearOutput, x) = x
pred(::PlanckOutput, x) = x.^4
pred(::FluxOutput,   x) = nothing










### 2) Decoding: Mutating single columns (used in online training)

# Define decodings of output vector Y (Y[k] are scalars)
@inline function decode!(of::DirectOutput, dT, Y::AbstractVector, col, consts)

    # Extract number of vertical layers
    n = length(col.T_prof)

    # Accumulate temperature tendencies
    for k in 1:n
        dT[k] += Y[k]
    end

    # Accumulate and return
    olw  = Y[n+1]
    slwd = Y[n+2]

    return olw, slwd
end


@inline function decode!(of::Union{LinearOutput, PlanckOutput}, dT, Y::AbstractVector, col, consts)

    # Extract number of vertical layers and calculate mid
    n = length(col.T_prof)
    mid = mid_layer(n)

    # Accumulate temperature tendencies
    for k in 1:n
        dT[k] += Y[k] + Y[n+k]*(pred(of, col.T_prof[k]) - consts.center.T[k])    # NOTE: center.T[k] is mean(p(T)), not p(mean(T))
    end

    # Accumulate and return fluxes
    olw  = Y[2n+1] + 
           Y[2n+2]*(pred(of, col.T_prof[mid]) - consts.center.T[mid]) + 
           Y[2n+3]*(pred(of, col.T_prof[end]) - consts.center.T[end])

    slwd = Y[2n+4] + 
           Y[2n+5]*(pred(of, col.T_prof[mid]) - consts.center.T[mid]) + 
           Y[2n+6]*(pred(of, col.T_prof[end]) - consts.center.T[end])

    return olw, slwd
end


@inline function decode!(of::FluxOutput, dT, Y::AbstractVector, col, consts)
    
    # Extract number of vertical layers and calculate mid
    n = length(col.T_prof)

    # Accumulate temperature tendencies
    for k in 1:n
        dT[k] += consts.flux_to_dT[k] / col.ps * (Y[k+1] - Y[k])
    end

    # Accumulate and return fluxes
    olw = Y[1]
    slwd = col.slwu - Y[n+1]

    return olw, slwd
end










### 3) Decoding: Mutating multiple columns (used in offline training)

# Define decodings of output matrix Y (shape: (n_out, n_grid))
@inline function decode(of::DirectOutput, Y::AbstractMatrix, col, consts)

    # Extract number of vertical layers
    n = size(col.T_prof, 1)

    # Return temperature tendencies and fluxes
    return (; dT = Y[1:n, :], olw = Y[n+1, :], slwd = Y[n+2, :])
end


@inline function decode(of::Union{LinearOutput, PlanckOutput}, Y::AbstractMatrix, col, consts)

    # Extract number of vertical layers and calculate mid
    n = size(col.T_prof, 1)
    mid = mid_layer(n)

    # Accumulate temperature tendencies
    dT = Y[1:n, :] .+ Y[n+1:2n, :] .* (pred(of, col.T_prof) .- consts.center.T)

    # Accumulate fluxes
    olw  = Y[2n+1, :] .+ 
           Y[2n+2, :] .* (pred(of, col.T_prof[mid, :]) .- consts.center.T[mid, :]) .+ 
           Y[2n+3, :] .* (pred(of, col.T_prof[end, :]) .- consts.center.T[end, :])

    slwd = Y[2n+4, :] .+ 
           Y[2n+5, :] .* (pred(of, col.T_prof[mid, :]) .- consts.center.T[mid, :]) .+ 
           Y[2n+6, :] .* (pred(of, col.T_prof[end, :]) .- consts.center.T[end, :])

    return (; dT, olw, slwd)
end


@inline function decode(of::FluxOutput, Y::AbstractMatrix, col, consts)
    
    # Extract number of vertical layers
    n = size(col.T_prof, 1)

    # Accumulate temperature tendencies
    dT = consts.flux_to_dT ./ reshape(col.ps, 1, :) .* (Y[2:n+1, :] - Y[1:n, :])

    # Accumulate and return fluxes
    olw = Y[1, :]
    slwd = col.slwu .- Y[n+1, :]

    return (; dT, olw, slwd)
end









### 4) Temperature tendency and flux writing

# Function for writing longwave tendencies and fluxes for online training (offline does not propagate)
@inline function write_lw!(ij, vars, model, emulator; Y)

    ### Write analytic flux tendencies
    sst = SpeedyWeather.get_prognostic_step(vars.prognostic.ocean.sea_surface_temperature, model.time_stepping, emulator)[ij]
    lst = vars.prognostic.land.soil_temperature[ij,1]
    lf = model.land_sea_mask.land_fraction[ij]
    σ = model.atmosphere.stefan_boltzmann

    U_sfc_ocean = ifelse(isfinite(sst), emulator.def_ocean_em * σ * sst^4, 0f0)
    U_sfc_land  = ifelse(isfinite(lst), emulator.def_land_em  * σ * lst^4, 0f0)
    slwu        = (1 - lf) * U_sfc_ocean + lf * U_sfc_land

    vars.parameterizations.ocean.surface_longwave_up[ij] = U_sfc_ocean
    vars.parameterizations.land.surface_longwave_up[ij] = U_sfc_land
    vars.parameterizations.surface_longwave_up[ij] = slwu


    
    ### Write temperature tendencies
    # Extract variables and prepare column data for decode!()
    T_prof = @view SpeedyWeather.get_prognostic_step(vars.grid.temperature, model.time_stepping, emulator)[ij,:]
    ps = vars.parameterizations.surface_pressure[ij]
    col = (; T_prof, ps, slwu)

    # Prepare consts for decode!()
    consts = (; center = emulator.zscore.center, flux_to_dT = emulator.flux_to_dT)


    # Extract and write temperature tendencies and get fluxes
    dTdt = @view SpeedyWeather.get_tendency_step(vars.tendencies.grid.temperature, model.time_stepping, emulator)[ij,:]
    olw, slwd = decode!(emulator.output_form, dTdt, Y, col, consts)



    ### Write NN flux tendencies
    vars.parameterizations.outgoing_longwave[ij] = olw
    vars.parameterizations.surface_longwave_down[ij] = slwd

    return nothing
end