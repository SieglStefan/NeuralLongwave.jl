### Tree utilities
###
### Functions for recursively handling parameter and gradient trees, e.g. for computing norms, scaling and adding





# Recursive squared L2 norms
tree_l2sum(x::Number)           = abs2(x)
tree_l2sum(x::AbstractArray)    = sum(abs2, x)
tree_l2sum(x::Tuple)            = sum(tree_l2sum, x)
tree_l2sum(x::NamedTuple)       = sum(tree_l2sum, values(x))

# Recursive L2 norm for parameter/gradient trees
tree_l2norm(x) = sqrt(tree_l2sum(x))



# Utility functions for adding parameter/gradient trees
tree_add(a::Number, b::Number)                = a + b
tree_add(a::AbstractArray, b::AbstractArray)  = a .+ b
tree_add(a::Tuple, b::Tuple)                  = map(tree_add, a, b)
tree_add(a::NamedTuple, b::NamedTuple)        = map(tree_add, a, b)

# Utility functions for scaling parameter/gradient trees
tree_scale(a::Number, s)        = a * s
tree_scale(a::AbstractArray, s) = a .* s
tree_scale(a::Tuple, s)         = map(x -> tree_scale(x, s), a)
tree_scale(a::NamedTuple, s)    = map(x -> tree_scale(x, s), a)