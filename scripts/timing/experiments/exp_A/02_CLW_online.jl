### TIMING - EXPERIMENT A - 02: ConstLW ONLINE
###
### Times the emulators trained by exp_A/02_CLW_online.jl against OBLW (the reference)
###
### The seeds share one architecture, so their times should agree - a check of the timing noise.





# Define series name (must match the training series it times)
SERIES_NAME = "02_CLW_online"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults())


# Output forms and seed indices (the same order as the training series)
FORMS = (:direct, :linear, :planck)
SEEDS = 1:3


# Reference first
BASELINES = [
    (; unit = "0_OBLW", baseline = :OBLW),
]

# Trained ConstLW emulators, one per output form and seed
UNITS = [(; unit = "online_$(form)_s$(j)") for form in FORMS for j in SEEDS]


# Define series: ONE job times all units
SERIES = vcat(BASELINES, UNITS)
