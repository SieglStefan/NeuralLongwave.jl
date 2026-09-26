### Restart States
###
### SpeedyWeather OBLW equilibrium states used for restarting simulations
###
### A restart state is (run, season), derived by scripts/targets/<SCHEME>/01_setup.jl:
###     - run       one of the 5 independent 10-year spinup runs (1-5)
###     - season    one of 13 states from the last year of that run, 4 weeks apart (1-13)
###
### The split is by run, so no evaluation ever starts from the climate a training run saw:
###     - run  1        setup studies (error growth / doubling time in 01_setup)
###     - runs 2-3      training   (offline training data, online training)
###     - runs 4-5      evaluation (weather reference, climate rollouts, timing)
###
### Every other file picks its restart states from these two lists





# Training: all seasons of runs 2-3
TRAIN_RESTARTS = [(run, season) for season in 1:13 for run in 2:3]

# Evaluation: every second season of runs 4-5
EVAL_RESTARTS  = [(run, season) for season in 1:2:11 for run in 4:5]
