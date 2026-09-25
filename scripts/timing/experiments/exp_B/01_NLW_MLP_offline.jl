### TIMING - EXPERIMENT B - 01: NeuralLW MLP OFFLINE
###
### Times the emulators trained by exp_B/01_NLW_MLP_offline.jl against OBLW (the reference)





# Define series name (must match the training series it times)
SERIES_NAME = "01_NLW_MLP_offline"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults())


# Sweep axes (the same order as the training series)
FORMS  = (:direct, :linear, :planck)
WIDTHS = (32, 64, 128)
DEPTHS = (1, 2, 3)


# Reference first, then the ZeroLW floor (the cost of the column loop itself)
BASELINES = [
    (; unit = "0_OBLW",   baseline = :OBLW),
    (; unit = "0_ZeroLW", baseline = :ZeroLW),
]

# Trained MLP emulators, one per (form, width, depth)
UNITS = [(; unit = "$(form)_w$(lpad(width, 3, '0'))_h$(depth)")
         for form in FORMS for width in WIDTHS for depth in DEPTHS]


# Define series: ONE job times all units
SERIES = vcat(BASELINES, UNITS)
