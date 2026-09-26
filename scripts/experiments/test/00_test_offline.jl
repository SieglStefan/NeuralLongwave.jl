### TEST: OFFLINE TRAINING + ROLLOUT + TIMING (runs locally in minutes)
###
### One tiny MLP trained offline on the test data of scripts/targets/OBLW/00_test.jl, rolled out and
### timed like a production experiment. Needs the whole OBLW 00_test pipeline first.
###
### Stages, in this order (in the REPL: ENV["STAGE"], ENV["GROUP"] = "test", ENV["SERIES"] = "00_test_offline", ENV["UNIT"]):
###     1) training
###     2) rollout
###     3) timing





# Define series name
SERIES_NAME = "00_test_offline"


# Stack the default blocks of every stage
DEFAULTS = (;
    training = merge(train_base(), train_oblw(), train_offline(), train_neurallw()),
    rollout  = merge(roll_base(),  roll_oblw(),  roll_weather(),  roll_climate()),
    timing   = merge(time_base(),  time_oblw()),
)


# Trained units
UNITS = [
    (;
        unit         = "test_mlp",
        overwrite    = true,

        zscore_unit  = "test",
        target_unit  = "test_training_data",
        target_trajs = 1:2,
        n_val_trajs  = 1,

        width        = 16,
        n_hidden     = 1,

        n_epochs     = 2,
        n_batches    = 5,
        batchsize    = 256,
    ),
]

# Baselines
OBLW = (; unit = "b_OBLW", baseline = :OBLW)


# Tiny rollout legs against the test weather reference and the test restart states
TINY_LEGS = (;
    weather_raw_series   = "00_test",
    weather_raw_unit     = "weather",
    weather_trajs        = 1:2,
    weather_horizon_days = 2,
    weather_n_starts     = 1,
    weather_field_days   = [1, 2],

    climate_restart_unit = "test",
    climate_restarts     = [(1, 1), (2, 1)],
    climate_n_years      = 2,
    climate_year_days    = 5,
)

# Few timing rounds from a test restart state (series-wide: taken from the first task)
FEW = (; n_warmup = 2, n_sweep_rounds = 10, n_step_rounds = 5, restart_unit = "test", restart = (1, 1))


# Define the tasks of every stage
SERIES = (;
    training = UNITS,
    rollout  = split_tasks(DEFAULTS.rollout, [weather_only(merge(OBLW, TINY_LEGS)); [merge(u, TINY_LEGS) for u in names_only(UNITS)]]),
    timing   = [merge(OBLW, FEW); names_only(UNITS)],
)
