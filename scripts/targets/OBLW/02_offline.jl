### OBLW 02: OFFLINE TRAINING DATA
###
### Raw training data (4 trajectories from training restart states), its column IO dataset and the
### zscore statistics. Analysed in evaluation/set_OBLW/03_correlation.ipynb and 04_zscore.ipynb.
###
###     - trajectories 1-3:     training, 
###     - trajectory 4:         validation (n_val_trajs = 1 in scripts/defaults/training.jl)
###     (the zscore statistics use all 4 trajectories (the validation trajectory included))
###
### Stages, in this order (needs the restart states of 01_setup):
###     1) raw_data     bash scripts/launch.sh raw_data OBLW 02_offline
###     2) derive       bash scripts/launch.sh derive   OBLW 02_offline





# Define series name
SERIES_NAME = "02_offline"


# Stack the default blocks of every stage
DEFAULTS = (;
    raw_data = merge(raw_base(), raw_oblw()),
    derive   = derive_base(),
)


# Define the tasks of every stage
SERIES = (;

    raw_data = [

        # 0: Training / validation data - 4 trajectories, 1 year each, ~daily
        (;
            unit            = "01_training_data",
            data_type       = :training,
            base_seed       = 1000,                                 # seeds 1001...1004
            starts          = [(2, 1), (3, 1), (2, 7), (3, 7)],     # training restarts, perturbed differently

            t_spinup        = Day(30),

            sim_days        = 365,
            sample_hours    = 24,
            phase_shift     = -1,
            offset_hours    = 6f0,
        ),
    ],


    derive = [

        # 0: Column IO dataset, then the zscore statistics fitted on it
        #       -> data/column_io/OBLW/training_data/, data/zscore/OBLW/default/
        (;
            unit            = "training_data",
            steps           = (:column_io, :zscore),
            raw_unit        = "01_training_data",
            trajs           = 1:4,
            column_io_unit  = "training_data",
            zscore_unit     = "default",
        ),
    ],
)
