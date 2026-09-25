### OBLW REFERENCE RAW DATA GENERATION
###
### Configuration for OBLW weather reference raw data used for rollouts:
###     - weather: one year per IC, sub-daily (8h), two ICs
###     - climate: no stored reference any more - it is the rollout unit 0_OBLW itself





# Define series name
SERIES_NAME = "03_reference"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults())


# Define series
SERIES = [

    # 0: Weather reference - 1 year per IC, every 8 hours
    (;
        unit            = "weather",
        n_ic            = 2,
        data_type       = :evaluation,
        base_seed       = 3000,

        target_type     = :OBLW,

        t_spinup        = Day(30),

        restart_scheme  = "OBLW",
        restart_unit    = "default",
        restart_ic      = 4,
        restart_j       = 1,

        sim_days        = 365 + 14 + 1,     # 1 year (+ overlap + safety)  
        sample_hours    = 8f0,              # 3 samples per day
        phase_shift     = 0,
        offset_hours    = 4f0,              # stagger the ICs against each other
    ),
]
