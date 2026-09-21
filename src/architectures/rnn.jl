### Recurrent Neural Network architecture
###
### Defining struct and helper setup function
###         - 1) Configuration
###         - 2) Layer
###         - 3) Forward pass
###         - 4) Setup
###
### Important: carry is a container for states:
###     - vanilla BiRNN:    only the flux state h
###     - LSTM BiRNN:       flux state h and memory c










### 1) Configuration

# RNN configuration struct
@kwdef struct RNNConfig{A} <: AbstractArchConfig
    cell::Symbol = :vanilla     # used recurrent cell: :vanilla or :lstm
    width::Int = 16             # width of the hidden state carried between layers

    act::A = tanh               # activation function inside the cell
end


# Define info data for a RNN architecture
info_arch(c::RNNConfig) = (; cell=string(c.cell), width=c.width, act=string(c.act))










### 2) Layer

### Vertical bidirectional RNN over the atmospheric column
###
### Two recurrent sweeps mirroring the two beams of radiative transfer:
###     - upward   beam: surface -> TOA,  initialized from the surface temperatures and scalars
###     - downward beam: TOA -> surface,  initialized with zeros (space emits nothing)
struct VerticalRNN{U,D,F,E} <: Lux.AbstractLuxContainerLayer{
        (:cell_up, :cell_down, :head_flux, :enc_sfc)}

    cell_up::U                  # recurrent cell of the upward beam
    cell_down::D                # recurrent cell of the downward beam

    head_flux::F                # flux states between layers (+scalars) -> net flux
    enc_sfc::E                  # scalar inputs -> initial hidden state of the upward beam

    nlayers::Int                # number of vertical layers
    width::Int                  # width (dimension) of the hidden state

    p_idx::Matrix{Int}          # row of X holding profile variable (e.g. temperature), column the layer
    s_idx::Vector{Int}          # row of X holding the scalar inputs
end










### 3) Forward pass

# Extract variables with pre-determined variable ranges (e.g. T_range = 1:8)
#   - online: X ... Vector
@inline function layer_features(m::VerticalRNN, X::AbstractVector, k)
    
    # Return merged variable vector
    return vcat(
        X[view(m.p_idx, :, k)],                         # temperature
        X[m.s_idx],                                     # scalars
        eltype(X)(k / m.nlayers)                        # layer fraction
    )
end

#   - offline: X ... Matrix
@inline function layer_features(m::VerticalRNN, X::AbstractMatrix, k)
    
    # Return merged variable vector
    return vcat(
        X[view(m.p_idx, :, k), :],                      # temperature
        X[m.s_idx, :],                                  # scalars
        fill(eltype(X)(k / m.nlayers), 1, size(X,2)),   # layer fraction
    )
end



# Upward beam: state n+1 (surface) -> state 1 (TOA)
function sweep_up(cell, xs, carry0, ps, st, n)
    
    # Define state vector and initialize first state (surface)
    carry = Vector{typeof(carry0)}(undef, n + 1)
    carry[n + 1] = carry0

    # Loop upward and return final state
    for k in n:-1:1
        carry[k] = step_cell(cell, xs[k], carry[k + 1], ps, st)
    end

    return carry
end

# Downward beam: state 1 (TOA) -> state n+1 (surface)
function sweep_down(cell, xs, carry0, ps, st, n)

    # Define state vector and initialize first state (TOA)
    carry = Vector{typeof(carry0)}(undef, n + 1)
    carry[1] = carry0

    # Loop downard and return final state
    for k in 1:n
        carry[k + 1] = step_cell(cell, xs[k], carry[k], ps, st)
    end

    return carry
end



# Complete forward pass X (complete input vector: T, ps, sinlat2,...) -> Y (net fluxes)
#   - online: X ... Vector
function (m::VerticalRNN)(X::AbstractVector, ps, st)

    # Derive number of vertical layers and scalars
    n = m.nlayers
    s = X[m.s_idx]                                      

    # Per-layer inputs of the two sweeps
    xs = [layer_features(m, X, k) for k in 1:n]


    # Boundary conditions: surface emission drives the upward beam, space emits nothing
    enc, _ = m.enc_sfc(s, ps.enc_sfc, st.enc_sfc)
    carry0_up = init_carry(m.cell_up, enc, m.width)
    carry0_down = init_carry(m.cell_down, zeros(eltype(X), n_state(m.cell_down) * m.width), m.width)

    # The two beams, giving one hidden state per interface
    carry_up   = sweep_up(  m.cell_up,   xs, carry0_up,   ps.cell_up,   st.cell_up,   n)
    carry_down = sweep_down(m.cell_down, xs, carry0_down, ps.cell_down, st.cell_down, n)

    
    # Extract and return net fluxes out of upward and downward beam
    net_fluxes = [first(m.head_flux(    
        vcat(readout(m.cell_up, carry_up[k]), readout(m.cell_down, carry_down[k]), s), 
        ps.head_flux, 
        st.head_flux
    ))[1] for k in 1:n+1]

    return net_fluxes, st
end

#   - offline: X ... Matrix
function (m::VerticalRNN)(X::AbstractMatrix, ps, st)

    # Derive number of vertical layers and scalars
    n = m.nlayers
    s = X[m.s_idx, :]                                      

    # Per-layer inputs of the two sweeps
    xs = [layer_features(m, X, k) for k in 1:n]


    # Boundary conditions: surface emission drives the upward beam, space emits nothing
    enc, _ = m.enc_sfc(s, ps.enc_sfc, st.enc_sfc)
    carry0_up = init_carry(m.cell_up, enc, m.width)
    carry0_down = init_carry(m.cell_down, zeros(eltype(X), n_state(m.cell_down) * m.width, size(X,2)), m.width)

    # The two beams, giving one hidden state per interface
    carry_up   = sweep_up(  m.cell_up,   xs, carry0_up,   ps.cell_up,   st.cell_up,   n)
    carry_down = sweep_down(m.cell_down, xs, carry0_down, ps.cell_down, st.cell_down, n)

    
    # Extract and return net fluxes out of upward and downward beam
    net_fluxes = reduce(vcat, [first(m.head_flux(
        vcat(readout(m.cell_up, carry_up[k]), readout(m.cell_down, carry_down[k]), s),
        ps.head_flux, 
        st.head_flux
    )) for k in 1:(n + 1)])

    return net_fluxes, st
end










### 4) Setup

# Setting up the vertical RNN architecture
function setup_arch(
    arch_config::RNNConfig,
    n_in::Int,
    n_out::Int,
    rng = Random.default_rng();
    input_spec,
    nlayers,
)

    # Extract nn architecture parameters
    (; cell, width, act) = arch_config


    # Derive layout NamedTuple for (; input_name = range)
    layout = input_layout(input_spec, nlayers)

    # Extract input variable keys
    profiles = [k for k in keys(input_spec) if input_spec[k].kind == :profile]
    scalars  = [k for k in keys(input_spec) if input_spec[k].kind == :scalar]

    # Define index ranges
    p_idx = Int[layout[p][k] for p in profiles, k in 1:nlayers]
    s_idx = Int[layout[s][1] for s in scalars]

    # Only FluxOutput is supported so far: Y = [net_fluxes]
    n_out == nlayers + 1 || error("VerticalRNN supports currently FluxOutput only: n_out=$n_out, expected $(nlayers+1)")



    # Feature vector of one layer: its temperature, the column scalars, its position
    n_scalar = size(s_idx, 1)
    n_feat   = size(p_idx, 1) + n_scalar + 1


    # Build the sub-layers
    cell_up   = build_cell(cell, n_feat, width, act)                    # upward beam cell
    cell_down = build_cell(cell, n_feat, width, act)                    # downward beam cell

    head_flux = Lux.Dense(2*width + n_scalar => 1)                      # merge flux states to net flux
    enc_sfc   = Lux.Dense(n_scalar => n_state(cell_up) * width, act)    # surface conditions -> initial upward state



    # Assemble the layer
    nn = VerticalRNN(
        cell_up, cell_down, 
        head_flux, enc_sfc,
        nlayers, width, 
        p_idx, s_idx,
    )


    # Setup NN
    ps, st = Lux.setup(rng, nn)
    st = Lux.testmode(st)

    return nn, ps, st
end