### Zscore functions
###
### Structs and functions for doing zscore transformations





### Transformations

# Calculate the z-score transformation of x
@inline zscore(x, μ, σ) = (x .- μ) ./ σ

# Calculate the inverse z-score transformation of z
@inline inv_zscore(z, μ, σ) = z .* σ .+ μ










### Struct Definition

# Struct holding zscore parameters
struct ZScoreStats{VI,VO,C}
    input_mean::VI          # input means, in the order of the scheme's input spec
    input_std::VI           # input stds

    output_mean::VO         # output means, in the order decode expects
    output_std::VO          # output stds
    center::C               # predictor center of the output form

    zscore_name::String     # name of the stats file
end

# Convenience constructor loading pre-calculated stats
function ZScoreStats(zscore_scheme::String, zscore_unit::String, input_spec, output_form)

    # Load zscore stats
    data = load(; dir=zscore_dir(zscore_scheme, zscore_unit), file="zscore.jld2")


    # Collect input mean and std in the order of input_spec
    input_mean, input_std = collect_zscore(data.fields, keys(input_spec))


    # Collect output mean and std in the order decode expects
    group = data[output_group(output_form)]
    output_mean, output_std = collect_zscore(group, output_keys(output_form))

    # Collect predictor center of the output form
    center = collect_center(group)


    return ZScoreStats(input_mean, input_std, output_mean, output_std, center, "$(zscore_scheme)_$(zscore_unit)")
end










### Collect zscore stats

# Collects zscore mean and std from a given group for a list of names
function collect_zscore(group, names)

    # Prepare mean and std containers
    mean = Float32[]
    std  = Float32[]

    # Collect mean/std for each var in names
    for var in names

        # Throw error if var is not represented in the stats file
        if !haskey(group, var)
            error("Zscore stats have no $var entry! Available: $(keys(group)).")
        end

        # Append mean and std container
        append!(mean, Float32.(group[var].mean))
        append!(std,  Float32.(group[var].std))
    end

    return mean, std
end

# Collects center of predictors
function collect_center(group)

    # Check if group has a :center entry
    haskey(group, :center) || return nothing

    # Return center of predictors
    return (; T = Float32.(group.center.T))
end
