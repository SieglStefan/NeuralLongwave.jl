### ROLLOUT TEST: SPLIT TASKS
###
### Small version of a production series, split with split_tasks exactly like the real ones, runs locally:
###     - weather: the tiny test reference raw_data/OBLW/00_test/2_weather_ref (1 IC, 1 start, 2 days)
###     - climate: 2 restarts (IC 4 and 5) x 2 "years" of 30 days (climate_year_days = 30, tests only)
###     - the emulator is loaded from results/test/00_test_climate/<unit>/emulator/emulator.jld2
###       (copy any trained emulator there first)
###     - the last unit runs both legs in ONE task: its climate leg must equal the one of 0_OBLW bit for bit





# Define series name
SERIES_NAME = "00_test_climate"


# Stack the default blocks (both legs)
DEFAULTS = merge(base_defaults(), oblw_defaults(), weather_defaults(), climate_defaults())


# Shared small leg settings
SMALL = (;
    weather_raw_series   = "00_test",
    weather_raw_unit     = "2_weather_ref",
    weather_ic_subset    = 1:1,
    weather_horizon_days = 2,
    weather_n_starts     = 1,
    weather_field_days   = [1, 2],

    climate_restarts     = [(4, 1), (5, 1)],    # two trajectories from two restart ICs (the spread needs at least two)
    climate_n_years      = 2,       # two yearly means
    climate_year_days    = 30,      # of 30 days each
)


# Units split like production: one weather and one climate task
UNITS = [
    (; unit = "0_OBLW",         baseline = :OBLW, SMALL...),                                 # reference (A)
    (; unit = "0_OBLW_pert",    baseline = :OBLW, SMALL..., climate_fac_pert_T = 0.02f0),    # noise floor (B)
    (; unit = "direct_w064_h2", SMALL...),                                                   # trained emulator
]

# Define series: 3 units as weather + climate task (0-5), plus one unit with both legs in one task (6)
SERIES = vcat(
    split_tasks(DEFAULTS, UNITS),
    [(; unit = "0_OBLW_whole", baseline = :OBLW, SMALL...)],
)
