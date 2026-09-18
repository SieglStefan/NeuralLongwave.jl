### Input handling
###
### Utilities for extracting and preprocessing emulator inputs
###         - 1) Input variable extracting functions
###         - 2) Input format handling
###         - 3) Input filling functions










### 1) Input variable extracting functions

# Temperature profile
@inline function in_T(X, o, ij, vars, model, scheme)

    # Extract temperature profile
    T = SpeedyWeather.get_prognostic_step(vars.grid.temperature, model.time_stepping, scheme)

    # Write temperature to input vector X
    for k in axes(T, 2)
        X[o+k] = T[ij,k]
    end
    
    # Return increased offset for next input variable
    return o + size(T, 2)
end

# Humidity profile
@inline function in_log10q(X, o, ij, vars, model, scheme)

    # Extract humidity profile
    q = SpeedyWeather.get_prognostic_step(vars.grid.humidity, model.time_stepping, scheme)

    # Write humidity to input vector X
    for k in axes(q, 2)
        X[o+k] = log10(q[ij,k] + 1e-7)
    end

    # Return increased offset for next input variable
    return o + size(q, 2)
end



# Bare scalar inputs
@inline in_sst(     X, o, ij, vars, model, scheme)  = (X[o+1] = SpeedyWeather.get_prognostic_step(vars.prognostic.ocean.sea_surface_temperature, model.time_stepping, scheme)[ij]; o+1)
@inline in_lst(     X, o, ij, vars, model, scheme)  = (X[o+1] = vars.prognostic.land.soil_temperature[ij,1]; o+1)
@inline in_lf(      X, o, ij, vars, model, scheme)  = (X[o+1] = model.land_sea_mask.land_fraction[ij]; o+1)
@inline in_sinlat2( X, o, ij, vars, model, scheme)  = (X[o+1] = sind(model.geometry.latds[ij])^2; o+1)
@inline in_p(       X, o, ij, vars, model, scheme)  = (X[o+1] = vars.parameterizations.surface_pressure[ij]; o+1)



# Derived scalar inputs
@inline function in_Usfc(X, o, ij, vars, model, scheme)
    
    # Extract variables and Boltzmann constant
    sst = in_sst(X, o, ij, vars, model, scheme)
    lst = in_lst(X, o, ij, vars, model, scheme)
    lf = in_lf(X, o, ij, vars, model, scheme)
    sigma = model.atmosphere.stefan_boltzmann

    # Calculate respective land and surface fluxes
    U_s = ifelse(isfinite(sst), sst^4, 0f0)
    U_l = ifelse(isfinite(lst), lst^4, 0f0)

    # Combine fluxes
    X[o+1] = sigma * (lf*U_l + (1-lf)*U_s)

    return o+1
end










### 2) Input format handling

# Input dictionary of all available inputs
const INPUTS = (;
    # Profile inputs
        T           = (; func = in_T,       kind = :profile),           # temperature profile
        log10q      = (; func = in_log10q,  kind = :profile),           # log10 humidity profile
    # Scalar inputs
        sst         = (; func = in_sst,     kind = :scalar),            # sea surface temperature
        lst         = (; func = in_lst,     kind = :scalar),            # land surface temperature (top layer)
        lf          = (; func = in_lf,      kind = :scalar),            # land fraction
        sinlat2     = (; func = in_sinlat2, kind = :scalar),            # latitude
        p           = (; func = in_p,       kind = :scalar),            # surface pressure
        Usfc        = (; func = in_Usfc,    kind = :scalar),            # surface upward flux
)

# Function for selecting a set of inputs from the dictionary, example: input_spec([:T, :lf])   ->   (; T = (; func = in_T, kind = :profile), lf = ....)
input_spec(names::Vector{Symbol}) = NamedTuple{Tuple(names)}(map(n -> INPUTS[n], names))



# Total length of the input vector for a given input spec
n_inputs(input_spec, nlayers) = sum(e -> e.kind === :profile ? nlayers : 1, input_spec)

# Function for mapping every input to its slice of the input vector, e.g. (; T = 1:8, lf = 9:9)
function input_layout(input_spec, nlayers)

    offset = 0

    # Returns a vector of ranges by applying "entry -> body" to each entry of input_spec
    return map(input_spec) do entry

        # Length of this input and the range it occupies
        n = entry.kind === :profile ? nlayers : 1
        range = offset+1:offset+n
        offset += n

        return range
    end
end










### 3) Input filling functions

# XXX Function for filling the input buffer with the selected inputs
@generated function fill_inputs!(X, input_spec::NamedTuple{names}, ij, vars, model, scheme) where {names}

    # Building blocks
    calls = [:(o = input_spec.$n.func(X, o, ij, vars, model, scheme)) for n in names]

    # Generates for example:
    #   o = 0
    #   o = input_spec.T.func(X, o, ij, vars, model, scheme)
    #   o = input_spec.lf.func(...)
    #   o = ...
    #   return o
    return quote
        Base.@_propagate_inbounds_meta
        o = 0
        $(Expr(:block, calls...))
        return o
    end
end