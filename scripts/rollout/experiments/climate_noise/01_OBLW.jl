### ROLLOUT - CLIMATE NOISE: OBLW
###
### Reference climate and climate noise floor, generated ONCE and used by every climate evaluation:
###     - 0_OBLW        the target scheme itself: the reference climate (A)
###     - 0_OBLW_pert   the target scheme from perturbed start states: the noise floor (B - A)
###
### Climate leg only, at the production settings of scripts/rollout/defaults.jl. Every series that is
### evaluated against these must use the same restart states and sampling (checked in the evaluation).





# Define series name
SERIES_NAME = "01_OBLW"


# Stack the default blocks (climate leg only)
DEFAULTS = merge(base_defaults(), oblw_defaults(), climate_defaults())


# Units
UNITS = [
    (; unit = "0_OBLW",      baseline = :OBLW),
    (; unit = "0_OBLW_pert", baseline = :OBLW, climate_fac_pert_T = 0.02f0),
]

# Define series: 2 units, one climate task each
SERIES = split_tasks(DEFAULTS, UNITS)
