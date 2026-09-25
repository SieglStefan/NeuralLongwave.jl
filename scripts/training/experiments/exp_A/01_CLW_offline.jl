### EXPERIMENT A — 01: ConstLW OFFLINE
###
### Questions:  
###     - How well does a calibrated globally CONSTANT longwave scheme perform? 
###     - What role does output forms play?
###
### One unit per output form:
###     - Direct: dT_k, olw, slwd directly
###     - Linear: dT_k = a + b * T_k, olw/slwd = c + d * T_mid + e * T_bot
###     - Planck: similar to Linear, but with T^4





# Define series name
SERIES_NAME = "01_CLW_offline"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults(), offline_defaults(), constlw_defaults())


# Output forms of the comparison, unit name -> output form
FORMS = (:direct, :linear, :planck)


# Define series
SERIES = [

    (;
        unit        = "offline_$(form)",
        output_form = FORMS[form],

        eta0        = 1f-1,

        n_epochs    = 20
    )

    for form in FORMS
]
