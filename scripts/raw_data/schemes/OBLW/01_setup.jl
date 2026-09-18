### OBLW SPINUP RAW DATA GENERATION
###
### Configuration for the OBLW spinup and decorrelation study (evaluation/expA)





# Define series name
SERIES_NAME = "01_setup"


# Stack the default blocks
DEFAULTS = merge(base_defaults(), oblw_defaults())


# Define series
SERIES = [

    # 0: Spinup default SW IC to obtain restart states
    (;
        unit            = "01_restart_states",
        n_ic            = 5,
        data_type       = :general,
        base_seed       = 0,

        t_spinup        = Day(0),
        start_date      = DateTime(2000, 1, 1),

        restart_scheme  = nothing,
        restart_unit    = nothing,

        sim_days        = 10*365,
        sample_hours    = 7*24,
        phase_shift     = -1,
    ),



    # 1-6: Spinup for error growth line for 14 day rollouts
    [(;
        unit            = "02_error_growth_14days/r$(lpad(j, 2, '0'))",
        n_ic            = 5,
        data_type       = :general,
        base_seed       = 100 + 10*j,

        restart_ic      = 1,
        restart_j       = 2*j,

        sim_days        = 14,
        sample_hours    = 8,
        phase_shift     = -1,

        fac_pert_T      = 0.002f0,
        fac_pert_q      = 0f0,
    ) for j in 1:6]...,



    # 7-9: Spinup almost identical restart states to obtain doubling time and equilibrium RMSE
    [(;
        unit            = "03_error_growth_120days/r$(lpad(j, 2, '0'))",
        n_ic            = 5,
        data_type       = :general,
        base_seed       = 200 + 10*j,

        restart_ic      = 1,
        restart_j       = 4*j,

        sim_days        = 120,
        sample_hours    = 48,
        phase_shift     = -1,

        fac_pert_T      = 0.002f0,
        fac_pert_q      = 0f0,
    ) for j in 1:3]...,

]
