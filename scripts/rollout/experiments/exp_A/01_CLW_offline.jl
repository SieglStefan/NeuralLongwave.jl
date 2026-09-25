### ROLLOUT - EXPERIMENT A - 01: ConstLW OFFLINE
###
### Rolls out the emulators trained by scripts/training/experiments/exp_A/01_CLW_offline.jl,
### plus the two baselines the notebook scores everything against:
###     - 0_OBLW        the target scheme itself: weather reference check, and a parallel copy of the
###                     reference climate (must equal climate_noise/01_OBLW/0_OBLW in its years)
###     - 0_ZeroLW      no longwave at all, the zero-skill floor
###
### Both legs at the production settings of scripts/rollout/defaults.jl.





# Define series name (must match the training series it rolls out)
SERIES_NAME = "01_CLW_offline"


# Stack the default blocks (both legs)
DEFAULTS = merge(base_defaults(), oblw_defaults(), weather_defaults(), climate_defaults())


# Output forms of the comparison (the same order as the training series)
FORMS = (:direct, :linear, :planck)


# Baselines, rolled out here because this is the series the notebook loads them from
BASELINES = [
    (; unit = "0_OBLW",   baseline = :OBLW),        # reference check + parallel reference climate
    (; unit = "0_ZeroLW", baseline = :ZeroLW),      # zero-skill floor
]

# Trained ConstLW emulators, one per output form
UNITS = [(; unit = "offline_$(form)") for form in FORMS]


# Define series: 5 units, each split into a weather and a climate task
SERIES = split_tasks(DEFAULTS, vcat(BASELINES, UNITS))
