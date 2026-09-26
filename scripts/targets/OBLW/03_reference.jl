### OBLW 03: REFERENCE
###
### Everything every emulator is evaluated against, generated ONCE (all from evaluation restarts):
###     - raw_data  weather         weather reference: 2 trajectories of one year, every 8 hours
###     - rollout   climate_ref     the target itself from EVAL_RESTARTS: the reference climate
###     - rollout   climate_noise   the target from perturbed EVAL_RESTARTS: the climate noise floor
###         (EVAL_RESTARTS = [(run, season) for ...] defined in defaults/restarts.jl)
###     - rollout   grey            grey OneBandLongwave (constant transmissivity): a simpler physical scheme,
###                                 weather and climate - the bar a good emulator has to beat
###
### The rollouts are stored at results/OBLW/<unit>/ and use the production settings of
### scripts/defaults/rollout.jl, so every experiment is comparable (checked in the evaluation).
### Analysed in evaluation/set_OBLW/05_reference.ipynb, loaded by every experiment notebook.
###
### Stages (need the restart states of 01_setup):
###     1) raw_data         bash scripts/launch.sh raw_data OBLW 03_reference
###     2) rollout 0-3      bash scripts/launch.sh rollout  OBLW 03_reference        (task 2 needs the raw data of 1)





# Define series name
SERIES_NAME = "03_reference"


# Stack the default blocks of every stage
DEFAULTS = (;
    raw_data = merge(raw_base(), raw_oblw()),
    rollout  = merge(roll_base(), roll_oblw(), roll_weather(), roll_climate()),
)


# Define the tasks of every stage
SERIES = (;

    raw_data = [

        # 0: Weather reference - 2 trajectories from the evaluation restart (4, 1), perturbed differently
        (;
            unit            = "weather",
            data_type       = :evaluation,
            base_seed       = 3000,
            starts          = [(4, 1), (5, 1)],

            t_spinup        = Day(30),

            sim_days        = 365 + 14 + 1,     # 1 year (+ overlap + safety)
            sample_hours    = 8f0,              # 3 samples per day
            phase_shift     = 0,                # exactly 8 hours, so the lead times of the rollouts match
            offset_hours    = 4f0,              # stagger the trajectories against each other
        ),
    ],


    rollout = [

        # 0: Reference climate
        (; unit = "climate_ref",   baseline = :OBLW, weather_n_starts = 0),

        # 1: Climate noise floor
        (; unit = "climate_noise", baseline = :OBLW, weather_n_starts = 0, climate_fac_pert_T = 0.02f0),

        # 2-3: Grey OneBandLongwave, weather (2) and climate (3) leg
        split_tasks(DEFAULTS.rollout, [(; unit = "grey", baseline = :GreyLW)])...,
    ],
)
