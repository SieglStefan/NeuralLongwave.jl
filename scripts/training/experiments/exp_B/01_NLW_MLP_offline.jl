### EXPERIMENT B — 01: NeuralLW MLP OFFLINE (architecture sweep)
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





# Define series name
SERIES_NAME = "01_NLW_MLP_offline"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults(), offline_defaults(), neurallw_defaults())


# Output forms of the sweep, unit name -> output form
FORMS = (:direct, :linear, :planck)

# Architecture axes
WIDTHS = (32, 64, 128)          # width of the hidden layers
DEPTHS = (1, 2, 3)              # number of hidden layers


# Define series
SERIES = [

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

    for form in FORMS for width in WIDTHS for depth in DEPTHS
]
