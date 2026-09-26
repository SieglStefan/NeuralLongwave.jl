### OBLW 00: TEST (the whole target pipeline in miniature, runs locally in minutes)
###
### Every stage of 01_setup, 02_offline and 03_reference once, with tiny settings. Nothing touches the
### production data: the restart states go to restart_unit "test", every derived artifact and reference
### run is named test_*.
###
### Stages, in this order (in the REPL: ENV["STAGE"], ENV["GROUP"] = "OBLW", ENV["SERIES"] = "00_test", ENV["UNIT"]):
###     1) raw_data 0       spinup (2 runs from the SW default state, 20 days)
###     2) derive   0       restart states -> data/restart_states/OBLW/test/
###     3) raw_data 1-3     error growth, training data, weather reference (from the test restart states)
###     4) derive   1-3     spinup statistics, error growth, column IO + zscore
###     5) rollout  0-3     test_climate_ref, test_climate_noise, test_grey (weather + climate)





# Define series name
SERIES_NAME = "00_test"


# Stack the default blocks of every stage
DEFAULTS = (;
    raw_data = merge(raw_base(), raw_oblw()),
    derive   = derive_base(),
    rollout  = merge(roll_base(), roll_oblw(), roll_weather(), roll_climate()),
)


# Restart states of the test (2 runs x 4 seasons, derived by derive task 0)
TEST_RESTARTS = [(1, 1), (2, 1)]

# Tiny rollout legs against the test weather reference and the test restart states
TINY_LEGS = (;
    weather_raw_series   = "00_test",
    weather_raw_unit     = "weather",
    weather_trajs        = 1:2,
    weather_horizon_days = 2,
    weather_n_starts     = 1,
    weather_field_days   = [1, 2],

    climate_restart_unit = "test",
    climate_restarts     = TEST_RESTARTS,
    climate_n_years      = 2,
    climate_year_days    = 5,
)


# Define the tasks of every stage
SERIES = (;

    raw_data = [

        # 0: Spinup - 2 runs from the SW default initial state, 20 days, daily
        (; unit = "spinup", starts = fill(:default, 2), sim_days = 20, sample_hours = 24, phase_shift = -1),

        # 1: Error growth - 3 slightly perturbed copies of the restart state (1, 2), 4 days
        (; unit = "error_growth/r01", starts = fill((1, 2), 3), restart_unit = "test",
           sim_days = 4, sample_hours = 24, phase_shift = -1, fac_pert_T = 0.001f0, fac_pert_q = 0f0),

        # 2: Training data - 2 trajectories, 4 days, ~daily
        (; unit = "training_data", data_type = :training, base_seed = 1000, starts = TEST_RESTARTS,
           restart_unit = "test", t_spinup = Day(1), sim_days = 4, sample_hours = 24, phase_shift = -1),

        # 3: Weather reference - 2 trajectories, 6 days, exactly daily
        (; unit = "weather", data_type = :evaluation, base_seed = 3000, starts = TEST_RESTARTS,
           restart_unit = "test", t_spinup = Day(1), sim_days = 6, sample_hours = 24, phase_shift = 0),
    ],


    derive = [

        # 0: Restart states (run, season) of the 2 spinup runs, 4 seasons 2 days apart
        (; unit = "test_restart_states", steps = (:restart_states,), raw_unit = "spinup", trajs = 1:2,
           restart_unit = "test", n_keep = 4, stride = 2),

        # 1: Spinup drift and RMSE cap  -> results/OBLW/test_spinup/
        (; unit = "test_spinup", steps = (:global_means, :rmse_caps), raw_unit = "spinup", trajs = 1:2, day_min = 10),

        # 2: Error growth  -> results/OBLW/test_error_growth/
        (; unit = "test_error_growth", steps = (:error_growth,), raw_units = ["error_growth/r01"], trajs = 1:3),

        # 3: Column IO + zscore  -> data/column_io/OBLW/test_training_data/, data/zscore/OBLW/test/
        (; unit = "test_training", steps = (:column_io, :zscore), raw_unit = "training_data", trajs = 1:2,
           column_io_unit = "test_training_data", zscore_unit = "test"),
    ],


    rollout = [

        # 0: Reference climate
        (; unit = "test_climate_ref",   baseline = :OBLW, TINY_LEGS..., weather_n_starts = 0),

        # 1: Climate noise floor
        (; unit = "test_climate_noise", baseline = :OBLW, TINY_LEGS..., weather_n_starts = 0, climate_fac_pert_T = 0.02f0),

        # 2-3: Grey OneBandLongwave, weather and climate leg
        split_tasks(DEFAULTS.rollout, [(; unit = "test_grey", baseline = :GreyLW, TINY_LEGS...)])...,
    ],
)
