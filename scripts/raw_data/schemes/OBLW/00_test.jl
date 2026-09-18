### OBLW TEST RAW DATA GENERATION
###
### Configuration for OBLW test raw data generation





# Define series name
SERIES_NAME = "00_test"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults())


# Define series
SERIES = [

    # 0: Training data test
    (;
        unit            = "1_training_data",
        overwrite       = true,
        n_ic            = 2,
        data_type       = :training,

        t_spinup        = Day(1),

        sim_days        = 10,
        sample_hours    = 24,
        phase_shift     = -1,
        offset_hours    = 2,
    ),



    # 1: Evaluation data test
    (;
        unit            = "2_weather_ref",
        overwrite       = true,
        n_ic            = 2,
        data_type       = :evaluation,

        t_spinup        = Day(1),

        sim_days        = 10,
        sample_hours    = 24,
        phase_shift     = 0,
        offset_hours    = 2,
    ),
]