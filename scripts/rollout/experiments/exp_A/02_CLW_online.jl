### ROLLOUT - EXPERIMENT A - 02: ConstLW ONLINE
###
### Rolls out the emulators trained by scripts/training/experiments/exp_A/02_CLW_online.jl.
###
### 0_OBLW is repeated here so this notebook can do its own reference check without reaching into
### the offline series. It is the same run as in 01_CLW_offline - drop it if the compute matters.
###
### Both legs at the production settings of scripts/rollout/defaults.jl.





# Define series name (must match the training series it rolls out)
SERIES_NAME = "02_CLW_online"


# Stack the default blocks (both legs)
DEFAULTS = merge(base_defaults(), oblw_defaults(), weather_defaults(), climate_defaults())


# Output forms and seed indices (the same order as the training series)
FORMS = (:direct, :linear, :planck)
SEEDS = 1:3


# Baseline, for the reference sanity check of this notebook
BASELINES = [
    (; unit = "0_OBLW", baseline = :OBLW),          # reference check + parallel reference climate
]

# Trained ConstLW emulators, one per output form and seed
UNITS = [(; unit = "online_$(form)_s$(j)") for form in FORMS for j in SEEDS]


# Define series: 10 units, each split into a weather and a climate task
SERIES = split_tasks(DEFAULTS, vcat(BASELINES, UNITS))
