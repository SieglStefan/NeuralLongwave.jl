### ConstLW Emulator
###
### Uses global constant parameters to emulate LW parameterization schemes
###     - 1) General Definition
###     - 2) SpeedyWeather Interface
###     - 3) Helper Functions










### 1) General Definition

# ConstLW emulator
struct ConstLW{P,O,Z} <: AbstractEmulatorLW
    ps::P                   # normalized scheme parameters for linearization

    output_form::O          # output form of scheme
    zscore::Z               # loaded zscore parameters

    def_ocean_em::Float32   # default ocean emissivity
    def_land_em::Float32    # default land emissivity
    def_co2::Float32        # default CO2 concentration
end


# Constructor for creating a ConstLW emulator
function ConstLW(;
    spectral_grid::SpectralGrid,
    output_form,
    zscore_scheme,
    zscore_unit,
    def_ocean_em = 0.98f0,      
    def_land_em = 0.98f0,      
    def_co2 = 280f0,           
)
  
    # Load zscore statistics (no inputs)
    zscore = ZScoreStats(zscore_scheme, zscore_unit, input_spec(Symbol[]), output_form)


    # Calculate input and output dimension
    n_out = length(zscore.output_mean)

    # Setup parameters
    ps = zeros(Float32, n_out)


    return ConstLW(
        ps,
        output_form, zscore,
        def_ocean_em, def_land_em, def_co2
    )
end











### 2) SpeedyWeather Interface

# Initializing function for SpeedyWeather (nothing is needed here yet)
function SpeedyWeather.initialize!(::ConstLW, ::PrimitiveEquation)
    return nothing
end


# SpeedyWeather parameterization function for updating temperature tendencies
Base.@propagate_inbounds function SpeedyWeather.parameterization!(
    ij,
    vars::SpeedyWeather.Variables,
    em::ConstLW,
    model::SpeedyWeather.AbstractModel,
)

    # Renormalize parameters
    Y = inv_zscore.(em.ps, em.zscore.output_mean, em.zscore.output_std)

    # Write tendencies
    write_lw!(ij, vars, model, em; Y)

    return nothing
end










### 3) Helper Functions

# Helper for updating ConstLW emulator parameters
function update_ps(em::ConstLW, ps_new)
    return ConstLW(
        ps_new,
        em.output_form, em.zscore,
        em.def_ocean_em, em.def_land_em, em.def_co2
    )
end


# Information about a ConstLW emulator
info_scheme(em::ConstLW) = (;
    scheme       = "ConstLW",

    ps           = em.ps,

    output_form  = string(nameof(typeof(em.output_form))),
    zscore_stats = em.zscore.zscore_name,

    def_ocean_em = em.def_ocean_em,
    def_land_em  = em.def_land_em,
    def_co2      = em.def_co2,
)

