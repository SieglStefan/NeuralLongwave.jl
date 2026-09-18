### ROLLOUT TEST: TRAINED EMULATOR
###
### Tiny rollout of the emulator trained by scripts/training/experiments/test/00_test_offline.jl,
### the last link of the chain test (raw data -> column_io -> zscore -> training -> rollout).
### Series and unit name mirror the training series, so the trained emulator is found.





# Define series name (must match the training series it rolls out)
SERIES_NAME = "00_test_offline"


# Stack the default blocks (both legs)
DEFAULTS = merge(base_defaults(), oblw_defaults(), weather_defaults(), climate_defaults())


# Define series
SERIES = [

    # 0: Trained test emulator
    (;
        unit                 = "test_offline",
        overwrite            = true,

        weather_ic_subset    = 1:1,
        weather_horizon_days = 2,
        weather_n_starts     = 2,
        weather_field_days   = [1, 2],

        climate_ic_subset    = 1:1,
        climate_horizon_days = 61,      # 9 samples = one full lap = one window
        climate_n_windows    = 1,
    ),
]
