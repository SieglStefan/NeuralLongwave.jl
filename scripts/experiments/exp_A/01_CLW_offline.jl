### EXPERIMENT A - 01: ConstLW OFFLINE
###
### Questions:
###     - How well does a calibrated globally CONSTANT longwave scheme perform?
###     - What role does output forms play?
###
### One unit per output form:
###     - Direct: dT_k, olw, slwd directly
###     - Linear: dT_k = a + b * T_k, olw/slwd = c + d * T_mid + e * T_bot
###     - Planck: similar to Linear, but with T^4
###
### Baselines (not trained, built from a recipe), and where they are generated:
###     - OBLW          the target       weather: b_OBLW here (sanity check, RMSE exactly 0), timing reference here
###                                      climate: results/OBLW/climate_ref     (targets/OBLW/03_reference.jl)
###     - OBLW pert.    climate noise    climate: results/OBLW/climate_noise   (targets/OBLW/03_reference.jl)
###     - GreyLW        simpler physics  weather + climate: results/OBLW/grey  (targets/OBLW/03_reference.jl)
###     - ZeroLW        no longwave      weather + climate + timing: b_ZeroLW here (zero-skill floor)
###
### Stages, in this order:
###     1) training     bash scripts/launch.sh training exp_A 01_CLW_offline
###     2) rollout      bash scripts/launch.sh rollout  exp_A 01_CLW_offline
###     3) timing       bash scripts/launch.sh timing   exp_A 01_CLW_offline





# Define series name
SERIES_NAME = "01_CLW_offline"


# Stack the default blocks of every stage
DEFAULTS = (;
    training = merge(train_base(), train_oblw(), train_offline(), train_constlw()),
    rollout  = merge(roll_base(),  roll_oblw(),  roll_weather(),  roll_climate()),
    timing   = merge(time_base(),  time_oblw()),
)


# Output forms of the comparison, unit name -> output form
FORMS = (; direct = DirectOutput(), linear = LinearOutput(), planck = PlanckOutput())


# Trained units
UNITS = [

    (;
        unit        = "offline_$(form)",
        output_form = FORMS[form],

        eta0        = 1f-1,

        n_epochs    = 20
    )

    for form in keys(FORMS)
]

# Baselines
OBLW   = (; unit = "b_OBLW",   baseline = :OBLW)
ZEROLW = (; unit = "b_ZeroLW", baseline = :ZeroLW)


# Define the tasks of every stage
#   - rollout: b_OBLW weather only, its climate is the reference results/OBLW/climate_ref
#   - timing:  the first task is the reference every runtime is relative to
SERIES = (;
    training = UNITS,
    rollout  = split_tasks(DEFAULTS.rollout, [weather_only(OBLW); ZEROLW; names_only(UNITS)]),
    timing   = [OBLW; ZEROLW; names_only(UNITS)],
)
