### Abstract emulator types for longwave parameterizations
###
### Structure:
###
### SpeedyWeather.AbstractLongwave          # longwave radiation parameterization scheme from SpeedyWeather
###     - AbstractEmulatorLW                    # emulators of this package
###         - ConstLW                               # constant parameters emulator
###         - NeuralLW                              # neural network emulator
###         - ZeroLW                                # zero flux emulator           





# Common supertype for all longwave emulators in this project
abstract type AbstractEmulatorLW <: SpeedyWeather.AbstractLongwave end