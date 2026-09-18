### ONLINE TRAINING TEST
###
### Series for testing online training of a NeuralLW emulator, with and without autodiff





# Define series name
SERIES_NAME = "00_test_online"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults(), online_defaults(), neurallw_defaults())


# Define series
SERIES = [

    # 0: Test NeuralLW online training without autodiff
    (;
        unit        = "test_online_no_autodiff",
        overwrite   = true,

        t_spinup    = Day(1),

        n_ic        = 2,
        n_updates   = 2,
        n_accum     = 2,
        n_seg_0     = 10,
        n_seg_inc   = 1,
        n_gap       = 1,

        do_autodiff = false,
    ),



    # 1: Test NeuralLW online training with autodiff
    (;
        unit        = "test_online_with_autodiff",
        overwrite   = true,

        t_spinup    = Day(1),

        n_ic        = 2,
        n_updates   = 2,
        n_accum     = 2,
        n_seg_0     = 10,
        n_seg_inc   = 1,
        n_gap       = 1,

        do_autodiff = true,
    ),
]
