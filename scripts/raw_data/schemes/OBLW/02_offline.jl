### OBLW DEFAULT RAW DATA GENERATION
###
### Configuration for OBLW offline training data





# Define series name
SERIES_NAME = "02_offline"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults())


# Define series
SERIES = [

    # 0: Training / Validation / Zscore
    (; 
        unit            = "01_training_data",           
        n_ic            = 4,                           
        data_type       = :training, 
        base_seed       = 1000,               # seeds 1001...1004

        t_spinup        = Day(30),

        restart_ic      = [1,2],
        restart_j       = 1,

        sim_days        = 365,
        sample_hours    = 24,
        phase_shift     = -1,
        offset_hours    = 6f0,
    ),
]