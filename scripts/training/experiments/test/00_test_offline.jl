### OFFLINE TRAINING TEST
###
### Series for testing offline training of a NeuralLW emulator, one unit per architecture
###     - MLP  with PlanckOutput (the batched Lux.Chain path)
###     - BiRNN with FluxOutput  (the batched VerticalRNN path, vanilla and LSTM cells)





# Define series name
SERIES_NAME = "00_test_offline"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults(), offline_defaults(), neurallw_defaults())


# Define series
SERIES = [

    # 0: Test NeuralLW offline training with an MLP
    (;
        unit        = "test_offline",
        overwrite   = true,

        target_ics  = 1:2,
        n_ic_val    = 1,

        n_epochs    = 2,
        n_batches   = 10,
        batchsize   = 1024,
    ),



    # 1: Test NeuralLW offline training with a BiRNN of vanilla cells
    (;
        unit        = "test_offline_rnn",
        overwrite   = true,

        arch_type   = :RNN,                     # VerticalRNN, carry is the flux state h
        output_form = FluxOutput(),             # BiRNN predicts net fluxes at the nlayers+1 interfaces

        target_ics  = 1:2,
        n_ic_val    = 1,

        n_epochs    = 2,
        n_batches   = 10,
        batchsize   = 1024,
    ),



    # 2: Test NeuralLW offline training with a BiRNN of LSTM cells
    (;
        unit        = "test_offline_lstm",
        overwrite   = true,

        arch_type   = :LSTM,                    # VerticalRNN, carry is the flux state h and the memory c
        output_form = FluxOutput(),

        target_ics  = 1:2,
        n_ic_val    = 1,

        n_epochs    = 2,
        n_batches   = 10,
        batchsize   = 1024,
    ),
]
