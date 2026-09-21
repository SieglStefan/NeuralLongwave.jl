### NeuralLW parameterization
###
### Uses a neural network to emulate LW parameterization schemes 
###     - 1) General Definition
###     - 2) SpeedyWeather Interface
###     - 3) Helper Functions










### 1) General Definition

# NeuralLongwave emulator
struct NeuralLW{N,P,S,C,I,O,Z,B,F} <: AbstractEmulatorLW
    nn::N                   # neural network (Lux)
    ps::P                   # parameters of the NN (Lux)
    st::S                   # state of the NN (Lux)

    arch_config::C          # architecture configuration of NN  
    input_spec::I           # list of inputs used in the emulator, e.g. (; T = (in_t, :profile), Ts = (in_ts, :scalar), ...)
    output_form::O          # output form of emulator, e.g. :linear
    zscore::Z               # loaded zscore parameters

    input_buffer::B         # input buffer to avoid allocation
    flux_to_dT::F           # flux to temperature tendencies conversion factor

    def_ocean_em::Float32   # default ocean emissivity
    def_land_em::Float32    # default land emissivity
    def_co2::Float32        # default CO2 concentration
end


# Constructor for creating Lux nn architecture and parameters
function NeuralLW(;
    spectral_grid::SpectralGrid,
    arch_config,
    input_spec,
    output_form,
    zscore_scheme,
    zscore_unit,
    def_ocean_em = 0.98f0,
    def_land_em = 0.98f0,
    def_co2 = 280f0,
    rng = Random.default_rng(),
)
  
    # Extract number of vertical layers
    nlayers = spectral_grid.nlayers

    # Load zscore statistics 
    zscore = ZScoreStats(zscore_scheme, zscore_unit, input_spec, output_form)


    # Calculate input and output dimension
    n_in = length(zscore.input_mean)
    n_out = length(zscore.output_mean)


    # Create nn architecture
    nn, ps, st = setup_arch(arch_config, n_in, n_out, rng; input_spec, nlayers)


    # Create empty input buffer
    input_buffer = zeros(Float32, n_in)

    # Calculate flux factor
    flux_to_dT = zeros(Float32, nlayers)


    return NeuralLW(
        nn, ps, st,
        arch_config, input_spec, output_form, zscore,
        input_buffer, flux_to_dT,
        def_ocean_em, def_land_em, def_co2
    )
end










### 2) SpeedyWeather Interface

# Initializing function for SpeedyWeather (calculate flux conversion factor)
function SpeedyWeather.initialize!(em::NeuralLW, model::PrimitiveEquation)
    
    # Calculate and assign conversion factors
    em.flux_to_dT .= flux_to_dT_fac(model)

    return nothing
end


# SpeedyWeather parameterization function for updating temperature tendencies
Base.@propagate_inbounds function SpeedyWeather.parameterization!(
    ij,
    vars::SpeedyWeather.Variables,
    em::NeuralLW,
    model::SpeedyWeather.AbstractModel,
)

    # Populate input buffer
    X = em.input_buffer
    fill_inputs!(X, em.input_spec, ij, vars, model, em)


    # Normalize input variables
    X .= zscore.(X, em.zscore.input_mean, em.zscore.input_std)

    # Lux forward pass
    Y, _ = Lux.apply(em.nn, X, em.ps, em.st)

    # Renormalize output variables
    Y .= inv_zscore.(Y, em.zscore.output_mean, em.zscore.output_std)


    # Write tendencies
    write_lw!(ij, vars, model, em; Y)

    return nothing
end










### 3) Helper Functions

# Helper for updating NeuralLW emulator parameters
function update_ps(em::NeuralLW, ps_new)
    return NeuralLW(
        em.nn, ps_new, em.st,
        em.arch_config, em.input_spec, em.output_form, em.zscore,
        em.input_buffer, em.flux_to_dT,
        em.def_ocean_em, em.def_land_em, em.def_co2
    )
end


# Define written info for NeuralLW parameterization emulator
info_scheme(em::NeuralLW) = (;
    scheme       = "NeuralLW",

    info_arch(em.arch_config)...,
    inputs       = collect(string.(keys(em.input_spec))),
    output_form  = string(nameof(typeof(em.output_form))),
    zscore_stats = em.zscore.zscore_name,

    def_ocean_em = em.def_ocean_em,
    def_land_em  = em.def_land_em,
    def_co2      = em.def_co2,
)
