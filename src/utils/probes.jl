### Probe utilities
###
### Defines probes and how to access their values from a model state
###         - 1) Constants and general probes
###         - 2) Weather and Climate probes










### 1) Constants and general probes

# Solar constant
const S0 = 1365f0



# Default probes
const PROBES = (;

    # Temperature
    T = (; 
        func = v -> SpeedyWeather.get_step(v.grid.temperature),   
        kind = :profile, 
        unit = "K"
    ),

    # Humidity
    q = (; 
        func = v -> SpeedyWeather.get_step(v.grid.humidity),
        kind = :profile, 
        unit = "kg/kg"
    ),


    # Outgoing longwave radiation
    olw = (; 
        func = v -> v.parameterizations.outgoing_longwave,        
        kind = :scalar,  
        unit = "W/m²"
    ),

    # Surface longwave down
    slwd = (; 
        func = v -> v.parameterizations.surface_longwave_down,    
        kind = :scalar,  
        unit = "W/m²"
    ),
        

    # Sea surface temperature
    sst = (; 
        func = v -> SpeedyWeather.get_step(v.prognostic.ocean.sea_surface_temperature), 
        kind = :scalar, 
        unit = "K"
    ),

    # Energy imbalance at the top of the atmosphere
    imb_TOA = (; 
        func = v -> S0 .* v.parameterizations.cos_zenith .- v.parameterizations.outgoing_shortwave .- v.parameterizations.outgoing_longwave, 
        kind = :scalar, 
        unit = "W/m²"
    ),
)










### 2) Weather and Climate probes

# Probes for weather evaluation
const WEATHER_PROBES = NamedTuple{(:T, :olw, :slwd)}(PROBES)

# Probes for climate evaluation
const CLIMATE_PROBES = NamedTuple{(:T, :olw, :slwd, :imb_TOA)}(PROBES)
