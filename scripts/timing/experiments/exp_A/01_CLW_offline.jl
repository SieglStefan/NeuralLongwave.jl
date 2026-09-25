### TIMING - EXPERIMENT A - 01: ConstLW OFFLINE
###
### Times the emulators trained by exp_A/01_CLW_offline.jl against OBLW (the reference)





# Define series name (must match the training series it times)
SERIES_NAME = "01_CLW_offline"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults())


# Output forms of the comparison (the same order as the training series)
FORMS = (:direct, :linear, :planck)


# Reference first, then the ZeroLW floor (the cost of the column loop itself)
BASELINES = [
    (; unit = "0_OBLW",   baseline = :OBLW),
    (; unit = "0_ZeroLW", baseline = :ZeroLW),
]

# Trained ConstLW emulators, one per output form
UNITS = [(; unit = "offline_$(form)") for form in FORMS]


# Define series: ONE job times all units
SERIES = vcat(BASELINES, UNITS)
