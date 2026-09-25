### Statistic Utilities
###
### Different statistics and metrics for evaluating data, losses and model performances
###         - 1) General metrics
###         - 2) Area weights
###         - 3) Linear Regression utilities










### 1) General metrics

# Root mean squared error
rmse(x, y) = sqrt(sum(abs2, x .- y) / length(x))

# Bias
bias(x, y) = sum(x .- y) / length(x)

# Correlation
correlation(x, y) = cor(vec(x), vec(y))

# Maximal absolute difference
maxdiff(x, y) = maximum(abs.(x .- y))



# Weighted metrics
wmean(x, w) = sum(w .* x) / length(x)
wrmse(x, y, w) = sqrt(wmean(abs2.(x .- y), w))
wbias(x, y, w) = wmean(x .- y, w)



# Field mean squared error, normalized by a normalization- and area weights
field_mse(r, norm, aw) = sum(aw .* (r ./ norm).^2) / length(r)



# Running mean over window samples, centered on its window, skipping non-finite values
#   - returns the shortened day axis and the smoothed samples
function running_mean(days, samples, window)

    # Define container for centers of windows and means of windows
    center_days  = Float64[]
    mean_samples = Float64[]

    # One mean per window start, only finite values count
    for start in 1:(length(samples) - window + 1)

        # Filter out non finite values in window range
        finite = filter(isfinite, view(samples, start:start+window-1))

        # Storre center of window and mean of window
        push!(center_days, days[start + window÷2])
        push!(mean_samples, isempty(finite) ? NaN : Float64(mean(finite)))
    end

    return center_days, mean_samples
end










### 2) Area weights

# Extracts area weights of a grid from a spectral grid
function area_weights(spectral_grid)

    # Extract grid from spectral_grid
    grid = spectral_grid.grid

    # Extract angles and rings
    Ω = get_solid_angles(grid)          # list of solid angle per grid cell for every ring from pole to pole
    rings = eachring(grid)              # point indices of every ring, e.g. 1:20, 21:44, ... 

    # Prepare weights array (one entry per grid point)
    w = zeros(Float32, get_npoints(grid))

    # Populate weights array with solid angles
    for (j, ring) in enumerate(rings)
        @views w[ring] .= Ω[j]
    end

    # Normalize weights so that mean weight = 1
    #   (mean(w)=1 instead of sum(w)=1 because it is more convenient for weighted averages)
    return w ./ mean(w)
end










### 3) Linear Regression utilities

# Fit y = a + b*x for one column
function fit_linear(x::AbstractVector, y::AbstractVector)
    
    # Transform to Float64, because Float32 is too inaccurate
    x = Float64.(x)
    y = Float64.(y)

    # Calculate mean of x and y
    x_bar = mean(x)
    y_bar = mean(y)

    # Calculate x-residual and apply linear regression
    dx  = x .- x_bar
    Sxx = sum(abs2, dx)
    b   = Sxx > 0 ? sum(dx .* (y .- y_bar)) / Sxx : 0.0

    # Return intercept, slope
    return Float32(y_bar - b*x_bar), Float32(b)
end


# Fit y = a + b*x1 + c*x2 for one column
function fit_linear(x1::AbstractVector, x2::AbstractVector, y::AbstractVector)

    # Transform to Float64, because Float32 is too inaccurate and calculate std
    x1 = Float64.(x1);  s1 = std(x1);  s1 = s1 > 0 ? s1 : 1.0
    x2 = Float64.(x2);  s2 = std(x2);  s2 = s2 > 0 ? s2 : 1.0

    # Apply bilinear regression
    A = hcat(ones(length(y)), x1 ./ s1, x2 ./ s2)
    c = A \ Float64.(y)

    # Return intercept, slope1, slope2
    return Float32(c[1]), Float32(c[2] / s1), Float32(c[3] / s2)
end