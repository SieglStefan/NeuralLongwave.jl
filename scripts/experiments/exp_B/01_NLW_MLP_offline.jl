### EXPERIMENT B - 01: NeuralLW MLP OFFLINE (architecture sweep)
###
### Questions:
###     - How well does a MLP perform?
###     - Which output form performs best?
###     - Which architecture (width and hidden layers) for online experiments?
###
### Sweep: (3 x 3 x 3)
###     - Outputforms:  Direct, Linear, Planck
###     - Width:        32, 64, 128
###     - Depth:        1,2,3
###
### Baselines (not trained, built from a recipe), and where they are generated:
###     - OBLW          the target       weather: b_OBLW here (sanity check, RMSE exactly 0), timing reference here
###                                      climate: results/OBLW/climate_ref     (targets/OBLW/03_reference.jl)
###     - OBLW pert.    climate noise    climate: results/OBLW/climate_noise   (targets/OBLW/03_reference.jl)
###
### Stages, in this order:
###     1) training     bash scripts/launch.sh training exp_B 01_NLW_MLP_offline
###     2) rollout      bash scripts/launch.sh rollout  exp_B 01_NLW_MLP_offline
###     3) timing       bash scripts/launch.sh timing   exp_B 01_NLW_MLP_offline





# Define series name
SERIES_NAME = "01_NLW_MLP_offline"


# Stack the default blocks of every stage
DEFAULTS = (;
    training = merge(train_base(), train_oblw(), train_offline(), train_neurallw()),
    rollout  = merge(roll_base(),  roll_oblw(),  roll_weather(),  roll_climate()),
    timing   = merge(time_base(),  time_oblw()),
)


# Output forms of the sweep, unit name -> output form
FORMS = (; direct = DirectOutput(), linear = LinearOutput(), planck = PlanckOutput())

# Architecture axes
WIDTHS = (32, 64, 128)          # width of the hidden layers
DEPTHS = (1, 2, 3)              # number of hidden layers


# Trained units
UNITS = [

    (;
        unit        = "$(form)_w$(lpad(width, 3, '0'))_h$(depth)",
        output_form = FORMS[form],

        arch_type   = :MLP,
        width       = width,
        n_hidden    = depth,
        act         = tanh,

        eta0        = 1f-2,

        n_epochs    = 60
    )

    for form in keys(FORMS) for width in WIDTHS for depth in DEPTHS
]

# Baselines
OBLW = (; unit = "b_OBLW", baseline = :OBLW)


# Define the tasks of every stage
#   - rollout: b_OBLW weather only, its climate is the reference results/OBLW/climate_ref
#   - timing:  the first task is the reference every runtime is relative to
SERIES = (;
    training = UNITS,
    rollout  = split_tasks(DEFAULTS.rollout, [weather_only(OBLW); names_only(UNITS)]),
    timing   = [OBLW; names_only(UNITS)],
)
