### EXPERIMENT B - 02: NeuralLW MLP ONLINE (continuation of the offline sweep)
###
### Questions:
###     - Does online training improve ConstLWs performance? (fine-tuning)
###
### Mode: Continued online training of offline trained schemes from B-01





# Define series name
SERIES_NAME = "02_NLW_MLP_online"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults(), online_defaults(), neurallw_defaults())


# Output forms of the comparison, unit name -> output form
FORMS = (:direct, :linear, :planck)

# Learning rates, unit name -> eta0
ETAS = (; eta13 = 1f-3, eta54 = 5f-4)

# Seed indices, one repetition each
SEEDS = 1:3


# Define series
SERIES = [

    (;
        unit            = "$(form)_$(eta)_s$(j)",
        output_form     = FORMS[form],
        seed            = 5000 + j,

        eta0            = ETAS[eta],

        init_experiment = "exp_B",            
        init_series     = "01_NLW_MLP_offline",
        init_unit       = "$(form)_w064_h3",

        arch_type       = :MLP,
        width           = 64,
        n_hidden        = 3,
        act             = tanh,
    )

    for form in FORMS for eta in keys(ETAS) for j in SEEDS
]
