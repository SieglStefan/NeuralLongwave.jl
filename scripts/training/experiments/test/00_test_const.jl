### OFFLINE TRAINING TEST: CONSTLW
###
### Series for testing offline training of a ConstLW emulator





# Define series name
SERIES_NAME = "00_test_const"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults(), offline_defaults(), constlw_defaults())


# Define series
SERIES = [

    # 0: Test ConstLW offline training
    (;
        unit        = "test_const",
        overwrite   = true,

        target_ics  = 1:2,
        n_ic_val    = 1,

        n_epochs    = 2,
        n_batches   = 10,
        batchsize   = 1024,
    ),
]
