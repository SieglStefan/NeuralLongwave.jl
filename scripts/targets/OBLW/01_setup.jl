### OBLW 01: SETUP
###
### The base of everything else:
###     - 5 independent spinup runs from the SW default initial state, 10 years each 
###             -> the restart states (run, season): the last year of every run, 13 seasons 4 weeks apart
###             -> RMSE cap (maximum global RMSE distance)
###     - the error growth study: 5 slightly perturbed copies of one restart state, 120 days
###             -> error growth curve, doubling time
### Analysed in evaluation/set_OBLW/01_restart_states.ipynb and 02_spinup.ipynb.
###
### Stages, in this order (the error growth runs start from the restart states):
###     1) raw_data 0       bash scripts/launch.sh raw_data OBLW 01_setup 0       spinup runs, 10 years
###     2) derive   0       bash scripts/launch.sh derive   OBLW 01_setup 0       derive restart states
###     3) raw_data 1-3     bash scripts/launch.sh raw_data OBLW 01_setup 1-3     error growth runs
###     4) derive   1-2     bash scripts/launch.sh derive   OBLW 01_setup 1-2     spinup statistics, error growth





# Define series name
SERIES_NAME = "01_setup"


# Stack the default blocks of every stage
DEFAULTS = (;
    raw_data = merge(raw_base(), raw_oblw()),
    derive   = derive_base(),
)


# Repetitions of the error growth runs (one raw unit each)
REPS_120 = ["03_error_growth_120days/r$(lpad(j, 2, '0'))" for j in 1:3]


# Define the tasks of every stage
SERIES = (;

    raw_data = [

        # 0: Spinup runs - 5 trajectories from the SW default initial state (trajectory k = run k)
        (;
            unit            = "01_restart_states",
            data_type       = :general,
            base_seed       = 0,                        # seeds 1...5
            starts          = fill(:default, 5),

            start_date      = DateTime(2000, 1, 1),

            sim_days        = 10*365,
            sample_hours    = 7*24,
            phase_shift     = -1,
        ),


        # 1-3: Error growth over 120 days - 5 perturbed copies of the restart state (1, 4j)
        [(;
            unit            = REPS_120[j],
            data_type       = :general,
            base_seed       = 200 + 10*j,               # seeds e.g. 211...213
            starts          = fill((1, 4*j), 5),

            sim_days        = 120,
            sample_hours    = 48,
            phase_shift     = -1,

            fac_pert_T      = 0.001f0,
            fac_pert_q      = 0f0,
        ) for j in 1:3]...,
    ],


    derive = [

        # 0: Restart states (run, season) of the 5 spinup runs  -> data/restart_states/OBLW/default/
        (;
            unit            = "restart_states",
            steps           = (:restart_states,),
            raw_unit        = "01_restart_states",
            trajs           = 1:5,
            restart_unit    = "default",
            n_keep          = 13,
            stride          = 4,
        ),

        # 1: Spinup drift and RMSE cap between the runs  -> results/OBLW/spinup/
        (;
            unit            = "spinup",
            steps           = (:global_means, :rmse_caps),
            raw_unit        = "01_restart_states",
            trajs           = 1:5,
            day_min         = 3*365,
        ),

        # 2: Error growth over 120 days  -> results/OBLW/error_growth_120days/
        (;
            unit            = "error_growth_120days",
            steps           = (:error_growth,),
            raw_units       = REPS_120,
            trajs           = 1:5,
        ),
    ],
)
