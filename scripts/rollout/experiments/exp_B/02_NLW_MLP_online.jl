### ROLLOUT - EXPERIMENT B - 02: NeuralLW MLP ONLINE
###
### Rolls out the 18 emulators trained by
### scripts/training/experiments/exp_B/02_NLW_MLP_online.jl, plus the reference.
###
### The offline counterparts these units continue (*_w064_h3) are rolled out in the
### 01_NLW_MLP_offline series - the notebook merges the two.
###
### Both legs at the production settings of scripts/rollout/defaults.jl.





# Define series name (must match the training series it rolls out)
SERIES_NAME = "02_NLW_MLP_online"


# Stack the default blocks (both legs)
DEFAULTS = merge(base_defaults(), oblw_defaults(), weather_defaults(), climate_defaults())


# Sweep axes (the same order as the training series)
FORMS = (:direct, :linear, :planck)
ETAS  = (:eta13, :eta54)
SEEDS = 1:3


# Baseline, for the reference sanity check
BASELINES = [
    (; unit = "0_OBLW", baseline = :OBLW),          # reference check + parallel reference climate
]

# Trained MLP emulators, one per (form, eta, seed)
UNITS = [(; unit = "$(form)_$(eta)_s$(j)") for form in FORMS for eta in ETAS for j in SEEDS]


# Define series: 19 units, each split into a weather and a climate task
SERIES = split_tasks(DEFAULTS, vcat(BASELINES, UNITS))
