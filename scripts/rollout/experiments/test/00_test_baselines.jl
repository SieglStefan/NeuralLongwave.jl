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

    climate_restarts     = [(4, 1)],    # one trajectory
    climate_n_years      = 1,       # one yearly mean (~10 min)
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

    # 2: Untrained ConstLW: ps = 0
    (;
        unit        = "0_ConstLW",
        baseline    = :ConstLW,
        overwrite   = true,
        TINY...,
    ),

    # 3: Target scheme from perturbed start states - climate noise floor
    (;
        unit               = "0_OBLW_pert",
        baseline           = :OBLW,
        overwrite          = true,
        TINY...,
        climate_fac_pert_T = 0.02f0,
    ),
]
