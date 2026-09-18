### Training Run
###
### Starts an offline or online training run depending on the config type (TrainConfigOffline or TrainConfigOnline)





# Run a training for a longwave parameterization scheme
function run_training(
    spectral_grid,          # spectral_grid of the model
    emulator,               # longwave parameterization scheme to be trained
    train_config,           # train configuration (TrainConfigOffline or TrainConfigOnline)
)

    # Run the optimization loop of the configured training mode
    emulator_trained = train(spectral_grid, emulator, train_config)


    # Save emulator after training
    save(emulator_trained; dir=train_config.dir, file="emulator.jld2")
    @info "Emulator $(train_config.unit) stored at $(train_config.dir)!"


    return emulator_trained
end



# Training mode, selected by the config type
train(sg, emulator, tc::TrainConfigOnline)  = training_online(;  spectral_grid=sg, emulator, tc)
train(sg, emulator, tc::TrainConfigOffline) = training_offline(; spectral_grid=sg, emulator, tc)