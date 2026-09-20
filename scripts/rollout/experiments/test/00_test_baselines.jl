### ROLLOUT TEST: BASELINES
###
### Tiny rollouts of two baselines against the real reference, small enough to run locally in minutes.
### Needs no trained emulator.





# Define series name
SERIES_NAME = "00_test_baselines"


# Stack the default blocks (both legs)
DEFAULTS = merge(base_defaults(), oblw_defaults(), weather_defaults(), climate_defaults())


# Shared tiny leg settings
TINY = (;
    weather_ic_subset    = 1:1,
    weather_horizon_days = 2,
    weather_n_starts     = 2,
    weather_field_days   = [1, 2],

    climate_ic_subset    = 1:1,
    climate_horizon_days = 61,      # 9 samples = one full lap = one window
    climate_n_windows    = 1,
)


# Define series
SERIES = [

    # 0: Target scheme - weather scores must be ~zero
    (;
        unit        = "0_OBLW",
        baseline    = :OBLW,
        overwrite   = true,
        TINY...,
    ),

    # 1: No LW parameterization at all
    (;
        unit        = "0_ZeroLW",
        baseline    = :ZeroLW,
        overwrite   = true,
        TINY...,
    ),
]
