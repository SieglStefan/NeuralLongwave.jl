### Scheme utilities
###
### Utilities for handling emulator and target schemes
###         - 1) Scheme Building
###         - 2) Scheme Information
###         - 3) Training Handling










### 1) Scheme Building

# Utility wrapper for building schemes based on their name
build_scheme(name::Symbol, SG; kwargs...) = build_scheme(Val(name), SG; kwargs...)

# Fallback for unknown schemes
build_scheme(v::Val, SG; kwargs...) = error("Unknown scheme recipe: $(typeof(v).parameters[1])")





# Build an OneBandLongwave target scheme given the spectral grid and emissivities
build_scheme(::Val{:OBLW}, SG; em_ocean = 0.98f0, em_land = 0.98f0, kwargs...) =
    OneBandLongwave(SG;
        transmissivity     = FriersonLongwaveTransmissivity(SG),
        radiative_transfer = OneBandLongwaveRadiativeTransfer(SG;
                                emissivity_ocean = em_ocean,
                                emissivity_land  = em_land))

# Build an AnalyticBandRadiation target scheme
build_scheme(::Val{:ABR}, SG; em_ocean = 1f0, em_land = 1f0, kwargs...) = nothing





# Build a ZeroLW emulator scheme
build_scheme(::Val{:ZeroLW}, SG; kwargs...) = ZeroLW()

# Build a ConstLW emulator scheme
build_scheme(::Val{:ConstLW}, SG; output_form, zscore_scheme, zscore_unit, em_ocean, em_land, co2, kwargs...) =
    ConstLW(;
        spectral_grid = SG,
        output_form   = output_form,
        zscore_scheme = zscore_scheme,
        zscore_unit   = zscore_unit,
        def_ocean_em  = em_ocean,
        def_land_em   = em_land,
        def_co2       = co2,
    )

# Build a NeuralLW emulator scheme, its architecture chosen by arch_type
function build_scheme(::Val{:NeuralLW}, SG; arch_type, n_hidden, width, act, inputs,
                      output_form, zscore_scheme, zscore_unit, em_ocean, em_land, co2, kwargs...)

    # Define architecture
    if arch_type == :MLP
        arch_config = MLPConfig(n_hidden = n_hidden, width = width, act = act)
    elseif arch_type == :RNN
        arch_config = RNNConfig(width = width, act = act)
    else
        error("Unknown architecture type: $(arch_type)")
    end

    return NeuralLW(;
        spectral_grid = SG,
        arch_config   = arch_config,
        input_spec    = input_spec(inputs),
        output_form   = output_form,
        zscore_scheme = zscore_scheme,
        zscore_unit   = zscore_unit,
        def_ocean_em  = em_ocean,
        def_land_em   = em_land,
        def_co2       = co2,
    )
end










### 2) Scheme Information

# Information about OneBandLongwave target
function info_scheme(scheme::OneBandLongwave)
    return (;
        scheme          = "OneBandLongwave",
        transmissivity  = string(nameof(typeof(scheme.transmissivity))),
        em_ocean        = scheme.radiative_transfer.emissivity_ocean,
        em_land         = scheme.radiative_transfer.emissivity_land,
    )
end

# Information about AnalyticBandRadiation target
#function info_scheme(scheme::AnalyticBandRadiation)
#    return nothing
#end










### 3) Training Handling

# Applys emulator in offline training to X = (n_in, n_batch) and returns the output
apply_offline(ps, ::Nothing, ::Nothing, X) = repeat(ps, 1, size(X, 2))          # ConstLW (no neural network, just parameters ps)
apply_offline(ps, nn, st, X) = first(Lux.apply(nn, X, ps, st))                  # NeuralLW


# Pieces of an emulator that offline training differentiates through
offline_parts(em::ConstLW)  = (nothing, nothing, em.zscore, em.output_form)                   
offline_parts(em::NeuralLW) = (em.nn, em.st, em.zscore, em.output_form)                         


# Input specification of an emulator
emulator_inputs(em::ConstLW)  = (;)                                                                  
emulator_inputs(em::NeuralLW) = em.input_spec                                                       



# Check that a loaded emulator matches the configuration it is continued under
function check_continuation(em, c)

    # Emulator type (nameof(typeof(em)) is e.g. :NeuralLW, so a mistyped emulator_type also errors)
    nameof(typeof(em)) === c.emulator_type ||
        error("Loaded emulator is a $(nameof(typeof(em))), config says $(c.emulator_type)!")

    # Output form
    typeof(em.output_form) === typeof(c.output_form) ||
        error("Loaded emulator has $(nameof(typeof(em.output_form))), config says $(nameof(typeof(c.output_form)))!")

    # Zscore statistics
    em.zscore.zscore_name == "$(c.zscore_scheme)_$(c.zscore_unit)" ||
        error("Loaded emulator uses zscore $(em.zscore.zscore_name), config says $(c.zscore_scheme)_$(c.zscore_unit)!")

    # Inputs (NeuralLW only, ConstLW has no inputs)
    if em isa NeuralLW
        keys(em.input_spec) == Tuple(c.inputs) ||
            error("Loaded emulator has inputs $(keys(em.input_spec)), config says $(Tuple(c.inputs))!")
    end

    return nothing
end