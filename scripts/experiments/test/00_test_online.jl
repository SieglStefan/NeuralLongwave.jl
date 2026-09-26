### TEST: ONLINE TRAINING (runs locally in minutes)
###
### One tiny MLP trained online WITHOUT autodiff (the Enzyme compile takes ~1 h), from the test restart
### states of scripts/targets/OBLW/00_test.jl. Exercises the start state selection (restarts, n_starts).
###
### Stages (in the REPL: ENV["STAGE"] = "training", ENV["GROUP"] = "test", ENV["SERIES"] = "00_test_online", ENV["UNIT"] = "0"):
###     - training





# Define series name
SERIES_NAME = "00_test_online"


# Stack the default blocks of every stage
DEFAULTS = (;
    training = merge(train_base(), train_oblw(), train_online(), train_neurallw()),
)


# Define the tasks of every stage
SERIES = (;

    training = [

        # 0: MLP online, without autodiff
        (;
            unit         = "test_online_no_autodiff",
            overwrite    = true,

            zscore_unit  = "test",
            restart_unit = "test",
            restarts     = [(run, season) for season in 1:4 for run in 1:2],

            width        = 16,
            n_hidden     = 1,

            t_spinup     = Day(1),
            n_starts     = 2,
            n_updates    = 2,
            n_accum      = 2,
            n_seg_0      = 5,
            n_seg_inc    = 1,
            n_gap        = 1,

            do_autodiff  = false,
        ),
    ],
)
