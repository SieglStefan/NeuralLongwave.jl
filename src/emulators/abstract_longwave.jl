### Abstract emulator types for longwave parameterizations
###
### Structure:
###
### SpeedyWeather.AbstractLongwave          # longwave radiation parameterization emulator from SpeedyWeather
###     - AbstractLW                            # emulators of this package
###         - ConstLW                               # constant parameters emulator
###         - NeuralLW                              # neural network emulator
###         - ZeroLW                                # zero flux emulator           





# Common supertype for all longwave emulator in this project
abstract type AbstractEmulatorLW <: SpeedyWeather.AbstractLongwave end