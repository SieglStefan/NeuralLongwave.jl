### Derive defaults
###
### Every key a derive task may set. A derive task turns raw data of the SAME target series into a
### derived artifact - the heavy steps that used to live in the evaluation/set_<SCHEME> notebooks:
###
###     DEFAULTS = (; raw_data = ..., derive = derive_base())
###
### The possible steps and their outputs are listed in scripts/stages/derive.jl.
###
### Every task is merged onto its defaults with checked_merge, so a key no stacked block defines is an error.










### 1) Base

# Keys shared by every derive task
derive_base() = (;

    # General
    unit            = "",                       # name of the task (results folder of the analysis steps)
    overwrite       = true,                     # whether an existing results folder is overwritten
    steps           = (),                       # derive steps, run in this order (see header in stages/derive.jl)


    # Raw data of THIS series the steps read
    raw_unit        = "",                       # one raw unit (restart_states, global_means, rmse_caps, column_io)
    raw_units       = String[],                 # several raw units (error_growth, e.g. repetitions r01, r02, ...)
    trajs           = 1:1,                      # trajectories of the raw data used (restart_states: the runs)


    # Restart states
    restart_unit    = "default",                # unit of the stored restart states
    n_keep          = 13,                       # seasons per run (13 x 4 weeks = one year)
    stride          = 4,                        # raw samples between two restart states


    # Spinup statistics (global_means, rmse_caps, error_growth)
    probes          = (:T, :olw, :slwd, :imb_TOA),  # probed fields
    day_min         = 3*365,                    # rmse_caps: tail (day > day_min) the saturated RMSE is averaged over


    # Column IO and zscore
    column_io_unit  = "training_data",          # unit of the column IO dataset (written by :column_io, read by :zscore)
    zscore_unit     = "default",                # unit of the zscore statistics
    zscore_forms    = (; linear = LinearOutput(), planck = PlanckOutput()),    # output forms fitted per column
)
