### ROLLOUT TEST: TRAINED EMULATOR
###
### Tiny rollout of the emulators trained by scripts/training/experiments/test/00_test_offline.jl,





# Define series name (must match the training series it rolls out)
SERIES_NAME = "00_test_offline"


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

    # 0: Trained test emulator (MLP)
    (;
        unit                 = "test_offline",
        overwrite            = true,

        TINY...,
    ),



    # 1: Trained test emulator (BiRNN, vanilla cells)
    (;
        unit                 = "test_offline_rnn",
        overwrite            = true,

        TINY...,
    ),



    # 2: Trained test emulator (BiRNN, LSTM cells)
    (;
        unit                 = "test_offline_lstm",
        overwrite            = true,

        TINY...,
    ),
]
