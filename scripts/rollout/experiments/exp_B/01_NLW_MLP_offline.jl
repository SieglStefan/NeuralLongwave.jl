### ROLLOUT - EXPERIMENT B - 01: NeuralLW MLP OFFLINE
###
### Rolls out the emulators trained by exp_B/01_NLW_MLP_offline.jl plus OBLW reference for sanity
###
### Both legs at the production settings of scripts/rollout/defaults.jl.





# Define series name (must match the training series it rolls out)
SERIES_NAME = "01_NLW_MLP_offline"


# Stack the default blocks (both legs)
DEFAULTS = merge(base_defaults(), oblw_defaults(), weather_defaults(), climate_defaults())


# Sweep axes (the same order as the training series)
FORMS  = (:direct, :linear, :planck)
WIDTHS = (32, 64, 128)
DEPTHS = (1, 2, 3)


# Baseline: reference check + parallel reference climate
BASELINES = [
    (; unit = "0_OBLW", baseline = :OBLW),
]

# Trained MLP emulators, one per (form, width, depth)
UNITS = [(; unit = "$(form)_w$(lpad(width, 3, '0'))_h$(depth)")
         for form in FORMS for width in WIDTHS for depth in DEPTHS]


# Define series: 28 units, each split into a weather and a climate task
SERIES = split_tasks(DEFAULTS, vcat(BASELINES, UNITS))
