### ONLINE TRAINING TEST
###
### Series for testing online training of a NeuralLW emulator, with and without autodiff
###
### The BiRNN units run with do_autodiff = false on purpose: they exercise the VerticalRNN
### vector forward pass inside SpeedyWeather without paying the ~1 h Enzyme compile per cell.





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
        restart_js  = 1:4,          # test raw data yields only 4 restart seasons (production: 1:13)

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
        restart_js  = 1:4,          # test raw data yields only 4 restart seasons (production: 1:13)

        do_autodiff = true,
    ),



    # 2: Test BiRNN of vanilla cells online, without autodiff
    (;
        unit        = "test_online_rnn_no_autodiff",
        overwrite   = true,

        arch_type   = :RNN,                     # VerticalRNN, carry is the flux state h
        output_form = FluxOutput(),             # BiRNN predicts net fluxes at the nlayers+1 interfaces

        t_spinup    = Day(1),

        n_ic        = 2,
        n_updates   = 2,
        n_accum     = 2,
        n_seg_0     = 10,
        n_seg_inc   = 1,
        n_gap       = 1,
        restart_js  = 1:4,          # test raw data yields only 4 restart seasons (production: 1:13)

        do_autodiff = false,
    ),



    # 3: Test BiRNN of LSTM cells online, without autodiff
    (;
        unit        = "test_online_lstm_no_autodiff",
        overwrite   = true,

        arch_type   = :LSTM,                    # VerticalRNN, carry is the flux state h and the memory c
        output_form = FluxOutput(),

        t_spinup    = Day(1),

        n_ic        = 2,
        n_updates   = 2,
        n_accum     = 2,
        n_seg_0     = 10,
        n_seg_inc   = 1,
        n_gap       = 1,
        restart_js  = 1:4,          # test raw data yields only 4 restart seasons (production: 1:13)

        do_autodiff = false,
    ),



    # 4: Test BiRNN of vanilla cells online, WITH autodiff (Enzyme through the timestepping)
    (;
        unit        = "test_online_rnn_with_autodiff",
        overwrite   = true,

        arch_type   = :RNN,
        output_form = FluxOutput(),

        t_spinup    = Day(1),

        n_ic        = 2,
        n_updates   = 2,
        n_accum     = 2,
        n_seg_0     = 10,
        n_seg_inc   = 1,
        n_gap       = 1,
        restart_js  = 1:4,          # test raw data yields only 4 restart seasons (production: 1:13)

        do_autodiff = true,
    ),



    # 5: Test BiRNN of LSTM cells online, WITH autodiff (Enzyme through the timestepping)
    (;
        unit        = "test_online_lstm_with_autodiff",
        overwrite   = true,

        arch_type   = :LSTM,
        output_form = FluxOutput(),

        t_spinup    = Day(1),

        n_ic        = 2,
        n_updates   = 2,
        n_accum     = 2,
        n_seg_0     = 10,
        n_seg_inc   = 1,
        n_gap       = 1,
        restart_js  = 1:4,          # test raw data yields only 4 restart seasons (production: 1:13)

        do_autodiff = true,
    ),
]
