### OFFLINE TRAINING TEST
###
### Series for testing offline training of a NeuralLW emulator





# Define series name
SERIES_NAME = "00_test_offline"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults(), offline_defaults(), neurallw_defaults())


# Define series
SERIES = [

    # 0: Test NeuralLW offline training
    (;
        unit        = "test_offline",
        overwrite   = true,

        target_ics  = 1:2,
        n_ic_val    = 1,

        n_epochs    = 2,
        n_batches   = 10,
        batchsize   = 1024,
    ),
]
