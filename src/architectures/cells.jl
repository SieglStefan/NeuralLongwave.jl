### Recurrent cells
###
### Building and setpping forward different BiRNN architecture cells
###         - 1) Cell building
###         - 2) Vanilla cell
###         - 3) LSTM cell










### 1) Cell building

# Utility wrapper for building cells based on their name
build_cell(name::Symbol, n_feat, width, act) = build_cell(Val(name), n_feat, width, act)

# Fallback for unknown cells
build_cell(v::Val, n_feat, width, act) = error("Unknown recurrent cell: $(typeof(v).parameters[1])")


# Build a vanilla cell
build_cell(::Val{:vanilla}, n_feat, width, act) = VanillaCell(Lux.Dense(n_feat + width => width, act))

# Build a LSTM cell
build_cell(::Val{:lstm}, n_feat, width, act) = LSTMCell(Lux.Dense(n_feat + width => 4*width))










### 1) Vanilla cell

# Vanilla BiRNN cell for multiple dispatch
#   - h_new = act(W * [x; h] + n)
#   - carry state is hidden state h
struct VanillaCell{D} <: Lux.AbstractLuxWrapperLayer{:dense}
    dense::D                    # Dense(n_feat + width => width, act)
end



# Number of state vectors carried between interfaces
#   - vanilla BiRNN: only h
n_state(::VanillaCell) = 1

# Build carry from surface encoder output
#   - already has the right form
init_carry(::VanillaCell, v, width) = v

# Extracting flux state h out of carry
readout(::VanillaCell, carry) = carry



# One recurrent update: layer features (x) + previous state (h) -> new state h'
@inline step_cell(cell::VanillaCell, x, carry, ps, st) = first(cell.dense(vcat(x, carry), ps, st))










### 3) LSTM cell

# LSTM BiRNN cell
#   - carry state is hidden state h and memory c
struct LSTMCell{D} <: Lux.AbstractLuxWrapperLayer{:dense}
    dense::D                    # Dense(n_feat + width => width, act)
end



# Number of state vectors carried between interfaces
#   - LSTM: h and c
n_state(::LSTMCell) = 2

# Build carry from surface encoder output
init_carry(::LSTMCell, v::AbstractVector, width) = (v[1:width], v[width+1:2*width])
init_carry(::LSTMCell, v::AbstractMatrix, width) = (v[1:width, :], v[width+1:2*width, :])

# Extracting flux state h out of carry
readout(::LSTMCell, carry) = carry[1]



# j-th block of width w out of the stacked gate vector (online) or matrix (offline)
#       - e.g. j = 3 leads to "candidate" gate
@inline gate_block(z::AbstractVector, j, w) = z[(j-1)*w+1 : j*w]
@inline gate_block(z::AbstractMatrix, j, w) = z[(j-1)*w+1 : j*w, :]



# One recurrent update: layer features (x) + previous carry (h, c) -> new carry (h', c')
#   - online: x ... Vector
@inline function step_cell(cell::LSTMCell, x::AbstractVector, carry, ps, st)

    # Unpack the carry and read the state width
    h, c = carry
    w = size(h, 1)

    # Gates: sigmoid for the three fractions, tanh for the signed candidate
    z = first(cell.dense(vcat(x, h), ps, st))
    i = Lux.sigmoid.(gate_block(z, 1, w))       # input:     how much of the candidate is written
    f = Lux.sigmoid.(gate_block(z, 2, w))       # forget:    how much of the memory survives (transmissivity)
    g = tanh.(       gate_block(z, 3, w))       # candidate: candidate contribution (emission)
    o = Lux.sigmoid.(gate_block(z, 4, w))       # output:    how much of the memory is exposed as h

    # Calculate new carries
    c_new = [f[k] * c[k] + i[k] * g[k] for k in 1:w]
    h_new = [o[k] * tanh(c_new[k])     for k in 1:w]

    return (h_new, c_new)
end

#   - offline: x ... Matrix
@inline function step_cell(cell::LSTMCell, x::AbstractMatrix, carry, ps, st)

    # Unpack the carry and read the state width
    h, c = carry
    w = size(h, 1)

    # Gates: sigmoid for the three fractions, tanh for the signed candidate
    z = lstm_gates(cell, x, h, ps, st)
    i = Lux.sigmoid.(gate_block(z, 1, w))
    f = Lux.sigmoid.(gate_block(z, 2, w))
    g = tanh.(       gate_block(z, 3, w))
    o = Lux.sigmoid.(gate_block(z, 4, w))

    # Calculate new carries
    c_new = f .* c .+ i .* g
    h_new = o .* tanh.(c_new)

    return (h_new, c_new)
end