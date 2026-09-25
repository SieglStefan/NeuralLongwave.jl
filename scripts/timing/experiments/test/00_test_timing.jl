### TIMING TEST: BASELINES
###
### Times the baselines against OBLW with few rounds, small enough to run locally in a minute.
### Needs no trained emulator.





# Define series name
SERIES_NAME = "00_test_timing"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults())


# Few rounds (set on the first unit, the series-wide settings are taken from it)
FEW = (; n_warmup = 3, n_sweep_rounds = 50, n_step_rounds = 20)


# Define series (first unit = reference)
SERIES = [
    (; unit = "0_OBLW",    baseline = :OBLW, FEW...),
    (; unit = "0_ZeroLW",  baseline = :ZeroLW),
    (; unit = "0_ConstLW", baseline = :ConstLW),
]
