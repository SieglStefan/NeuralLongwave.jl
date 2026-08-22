### NLW seeding experiment
###
### Questions:
###     - Are other architectures better at learning the NLW scheme than the default MLP architecture?



# Define experiment name
EXP = "exp_B_01_width"



# Define parameters for the experiment
CONFIG = (;
    lw_target_type = :OBLW,

    lw_train_type  = :NeuralLW,
    output_form    = DirectOutput(),

    eta0           = 1f-2,
    eta_decay      = 0.8f0,

    n_ic           = 10,
)



# Define experiments
experiments = [

    # 0: MLP
    (; name = "MLP_s1000", arch_type = :MLP, n_hidden = 2, width = 32, seed = 1000, CONFIG...),


    # 1: width = 8, seed = 1000
    (; name = "RNN_w8_s1000", arch_type = :RNN, width = 8, seed = 1000, CONFIG...),

    # 2: width = 16, seed = 1000
    (; name = "RNN_w16_s1000", arch_type = :RNN, width = 16, seed = 1000, CONFIG...),

    # 3: width = 32, seed = 1000
    (; name = "RNN_w32_s1000", arch_type = :RNN, width = 32, seed = 1000, CONFIG...),

    # 4: width = 64, seed = 1000
    (; name = "RNN_w64_s1000", arch_type = :RNN, width = 64, seed = 1000, CONFIG...),

    # 5: width = 128, seed = 1000
    (; name = "RNN_w128_s1000", arch_type = :RNN, width = 128, seed = 1000, CONFIG...),



    # 6: MLP
    (; name = "MLP_s2000", arch_type = :MLP, n_hidden = 2, width = 32, seed = 2000, CONFIG...),


    # 7: width = 8, seed = 2000
    (; name = "RNN_w8_s2000", arch_type = :RNN, width = 8, seed = 2000, CONFIG...),

    # 8: width = 16, seed = 2000
    (; name = "RNN_w16_s2000", arch_type = :RNN, width = 16, seed = 2000, CONFIG...),

    # 9: width = 32, seed = 2000
    (; name = "RNN_w32_s2000", arch_type = :RNN, width = 32, seed = 2000, CONFIG...),

    # 10: width = 64, seed = 2000
    (; name = "RNN_w64_s2000", arch_type = :RNN, width = 64, seed = 2000, CONFIG...),

    # 11: width = 128, seed = 2000
    (; name = "RNN_w128_s2000", arch_type = :RNN, width = 128, seed = 2000, CONFIG...),

]