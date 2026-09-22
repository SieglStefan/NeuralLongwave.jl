### OBLW REFERENCE RAW DATA GENERATION
###
### Configuration for OBLW weather and climate reference raw data used for rollouts:
###     - weather: one year per IC, sub-daily (8h), two ICs
###     - climate: three years per IC, ~weekly, four seasonal starts





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


    # 1: Climate reference - 3 years per IC, ~weekly, one start per season
    (;
        unit            = "climate",
        n_ic            = 4,
        data_type       = :evaluation,        
        base_seed       = 4000,

        target_type     = :OBLW,

        t_spinup        = Day(30),

        restart_scheme  = "OBLW",
        restart_unit    = "default",
        restart_ic      = 4,
        restart_j       = [1, 4, 7, 10],    # one start per season (Jan, Apr, Jul, Oct)

        sim_days        = 3*365 + 14 + 1,   # 3 years (+ safety)
        sample_hours    = 168f0,            # ~weekly, giving ~3*54 samples over 3 years
        phase_shift     = -8,               # precessing: eight steps short of a full week
        offset_hours    = 0f0,
    ),
]
