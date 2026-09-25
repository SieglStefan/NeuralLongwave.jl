### EXPERIMENT A - 02: ConstLW ONLINE
###
### Questions:
###     - Does online training improve ConstLWs performance? (fine-tuning)
###
### Mode: Continued online training of offline trained schemes from A-01





# Define series name
SERIES_NAME = "02_CLW_online"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults(), online_defaults(), constlw_defaults())


# Output forms of the comparison, unit name -> output form
FORMS = (:direct, :linear, :planck)

# Seed indices, one repetition each
SEEDS = 1:3


# Define series
SERIES = [

    (;
        unit            = "online_$(form)_s$(j)",
        output_form     = FORMS[form],
        seed            = 5000 + j,

        eta0            = 1f-2,

        init_experiment = "exp_A",
        init_series     = "01_CLW_offline",
        init_unit       = "offline_$(form)",
    )

    for form in FORMS for j in SEEDS
]
