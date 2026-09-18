### Recurrent Neural Network architecture
###
### Defining struct and helper setup function
###         - 1) Configuration
###         - 2) Layer
###         - 3) Forward pass
###         - 4) Setup
###
### IMPORTANT: Currently in construction and not finished yet! 










### 1) Configuration

# RNN configuration struct
@kwdef struct RNNConfig{A} <: AbstractArchConfig
    width::Int = 16             # width of the hidden state carried between layers

    act::A = tanh               # activation function inside the cell
end


# Define info data for a RNN neural network architecture
info_arch(c::RNNConfig) = (; width=c.width, act=string(c.act))










### 2) Layer

### Vertical bidirectional RNN over the atmospheric column
###
### Two recurrent sweeps mirroring the two beams of the radiative transfer solver:
###     - upward   beam: surface -> TOA,  initialized from the surface temperature
###     - downward beam: TOA -> surface,  initialized with zeros (space emits nothing)
### Hidden states live at the nlayers+1 interfaces; layer k is read from its two faces.
struct VerticalRNN{U,D,E,H,O,S} <: Lux.AbstractLuxContainerLayer{
        (:cell_up, :cell_down, :enc_sfc, :head_dT, :head_olw, :head_slwd)}

    cell_up::U                  # recurrent cell of the upward beam
    cell_down::D                # recurrent cell of the downward beam

    enc_sfc::E                  # scalar inputs -> initial hidden state of the upward beam

    head_dT::H                  # interface states around layer k (+ scalars) -> dT[k]
    head_olw::O                 # upward beam at TOA       -> olw
    head_slwd::S                # downward beam at surface -> slwd

    nlayers::Int                # number of vertical layers
    width::Int                  # width of the hidden state

    T_range::UnitRange{Int}     # slice of X holding the temperature profile
    S_range::UnitRange{Int}     # slice of X holding all scalar inputs
end










### 3) Forward pass

# One recurrent update — a vanilla RNN cell is a Dense layer applied to [x; h]
@inline step_cell(cell, x, h, ps, st) = first(cell(vcat(x, h), ps, st))


# Per-layer feature vector: this layer's temperature, the column scalars, and the position
@inline function layer_features(m::VerticalRNN, X::AbstractVector, k)
    return vcat(X[m.T_range[k]], X[m.S_range], eltype(X)(k / m.nlayers))
end


# Upward beam: interface n+1 (surface) -> interface 1 (TOA)
function sweep_up(cell, xs, h0, ps, st, n)
    hs = Vector{typeof(h0)}(undef, n + 1)
    hs[n + 1] = h0
    for k in n:-1:1
        hs[k] = step_cell(cell, xs[k], hs[k + 1], ps, st)
    end
    return hs
end

# Downward beam: interface 1 (TOA) -> interface n+1 (surface)
function sweep_down(cell, xs, h0, ps, st, n)
    hs = Vector{typeof(h0)}(undef, n + 1)
    hs[1] = h0
    for k in 1:n
        hs[k + 1] = step_cell(cell, xs[k], hs[k], ps, st)
    end
    return hs
end


# Lux forward pass: X (n_in) -> Y = [dT(1:n), olw, slwd]
function (m::VerticalRNN)(X::AbstractVector, ps, st)

    n = m.nlayers
    s = X[m.S_range]                                        # column scalars, reused throughout

    # Per-layer inputs of the two sweeps
    xs = [layer_features(m, X, k) for k in 1:n]

    # Boundary conditions: surface emission drives the upward beam, space emits nothing
    h0_up   = first(m.enc_sfc(s, ps.enc_sfc, st.enc_sfc))
    h0_down = zeros(eltype(X), m.width)

    # The two beams, giving one hidden state per interface
    h_up   = sweep_up(  m.cell_up,   xs, h0_up,   ps.cell_up,   st.cell_up,   n)
    h_down = sweep_down(m.cell_down, xs, h0_down, ps.cell_down, st.cell_down, n)

    # Tendencies: read layer k from the two beams at its two faces
    dT = [first(m.head_dT(vcat(h_up[k], h_up[k+1], h_down[k], h_down[k+1], s),
                          ps.head_dT, st.head_dT))[1] for k in 1:n]

    # Fluxes: the two beams where they leave the atmosphere
    olw  = first(m.head_olw( h_up[1],     ps.head_olw,  st.head_olw))
    slwd = first(m.head_slwd(h_down[n+1], ps.head_slwd, st.head_slwd))

    return vcat(dT, olw, slwd), st
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
    (; width, act) = arch_config


    # Locate the inputs in the flat input vector X
    layout = input_layout(input_spec, nlayers)

    T_range = layout.T                      # 1:nlayers
    S_range = (nlayers + 1):n_in            # everything after the profile


    # Only DirectOutput is supported so far: Y = [dT(1:n), olw, slwd]
    n_out == nlayers + 2 || error("VerticalRNN supports currently DirectOutput only: n_out=$n_out, expected $(nlayers+2)")


    # Feature vector of one layer: its temperature, the column scalars, its position
    n_scalar = length(S_range)
    n_feat   = 1 + n_scalar + 1


    # Build the sub-layers
    cell_up   = Lux.Dense(n_feat + width => width, act)     # one recurrent update, upward beam
    cell_down = Lux.Dense(n_feat + width => width, act)     # one recurrent update, downward beam

    enc_sfc   = Lux.Dense(n_scalar => width, act)           # surface conditions -> initial upward state

    head_dT   = Lux.Dense(4*width + n_scalar => 1)          # both beams at both faces of a layer -> dT
    head_olw  = Lux.Dense(width => 1)                       # upward beam at TOA       -> olw
    head_slwd = Lux.Dense(width => 1)                       # downward beam at surface -> slwd


    # Assemble the layer
    nn = VerticalRNN(
        cell_up, cell_down, enc_sfc,
        head_dT, head_olw, head_slwd,
        nlayers, width, T_range, S_range,
    )


    # Setup NN
    ps, st = Lux.setup(rng, nn)
    st = Lux.testmode(st)

    return nn, ps, st
end