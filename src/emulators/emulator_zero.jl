### ZeroLW parameterization
###
### Used as "no LW parameterization" for sanity checks and testing
###     - 1) General Definition and Helper Functions
###     - 2) SpeedyWeather Interface










### 1) General Definition and Helper Functions

# ZeroLW parameterization
struct ZeroLW <: AbstractEmulatorLW
end



# Helper function for updating parameterization parameters
function update_ps(em::ZeroLW, ps_new)
    return em
end

# Define written info for ZeroLW parameterization emulator
info_scheme(em::ZeroLW) = (;
    scheme       = "ZeroLW",
)










### 2) SpeedyWeather Interface

# Initializing function for SpeedyWeather
function SpeedyWeather.initialize!(::ZeroLW, ::PrimitiveEquation)
    return nothing
end

# SpeedyWeather parameterization function for updating temperature tendencies
Base.@propagate_inbounds function SpeedyWeather.parameterization!(
    ij,
    vars::SpeedyWeather.Variables,
    em::ZeroLW,
    model::SpeedyWeather.AbstractModel,
)

    # Write zero to all fluxes
    vars.parameterizations.outgoing_longwave[ij]         = 0f0
    vars.parameterizations.surface_longwave_down[ij]     = 0f0
    vars.parameterizations.ocean.surface_longwave_up[ij] = 0f0
    vars.parameterizations.land.surface_longwave_up[ij]  = 0f0
    vars.parameterizations.surface_longwave_up[ij]       = 0f0

    return nothing
end