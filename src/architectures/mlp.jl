### Multi Layer Perceptron architecture
###
### Defining struct and helper setup function
###         - 1) Configuration
###         - 2) Layer
###         - 3) Forward pass
###         - 4) Setup










### 1) Configuration

# MLP configuration struct
@kwdef struct MLPConfig{A} <: AbstractArchConfig
    n_hidden::Int = 2           # number of hidden layers
    width::Int = 32             # width of neural network
    
    act::A = tanh               # activation function
end


# Define info data for a MLP neural network architecture
info_arch(c::MLPConfig) = (; n_hidden=c.n_hidden, width=c.width, act=string(c.act))





### 2) Layer (none here, only plain Lux.Chain)

### 3) Forward pass (none here, only Lux.Chain's own forward pass)





### 4) Setup

# Setting up MLP architecture
function setup_arch(
    arch_config::MLPConfig,
    n_in::Int,
    n_out::Int,
    rng = Random.default_rng();
    kwargs...,                  # ignored: only the RNN needs input_spec / nlayers
)

    # Extract nn architecture parameters
    (; n_hidden, width, act) = arch_config


    # Build nn
    hidden = [Lux.Dense(width => width, act) for _ in 1:n_hidden-1]

    nn = Lux.Chain(
        Lux.Dense(n_in => width, act),
        hidden...,
        Lux.Dense(width => n_out),
    )


    # Setup NN
    ps, st = Lux.setup(rng, nn)
    st = Lux.testmode(st)

    return nn, ps, st
end