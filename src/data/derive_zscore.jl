### Zscore statistics derivation
###
### Functions for deriving zscore statistics (physical fields and affine coefficients) from a column IO dataset
###         - 1) Derive Zscore Statistics
###         - 2) Coefficient Fits
###         - 3) Statistics Helpers










### 1) Derive Zscore Statistics

# Derive zscore statistics from a raw dataset and store them as zscore.jld2
function derive_zscore(;
    column_io,              # column IO data used for zscore calculation
    coeffs,                 # coefficients of output forms
    scheme,                 # scheme folder for storing zscore stats
    unit,                   # unit folder for storing zscore stats
    fit_forms,              # list of fit forms used in the scheme
    seed = 6000,             
)
        
    # Set seed for reproducibility
    Random.seed!(seed)


    # Raw field stats for every sampled field, plus one fitted group per affine output form
    zscore = (;

        # All physical fields (input and output)
        fields = map(field_stats, column_io.fields),

        # All different output forms, fitted per column
        (g => (; map(coeff_stats, f.coeffs)..., center = f.center) for (g, f) in pairs(coeffs))...,

        # Shape metadata, checked when an emulator loads these stats
        dims = column_io.dims,
    )

    
    # Save zscore stats
    dir = zscore_dir(scheme, unit)
    save(zscore; dir, file = "zscore.jld2")

    # Store information about zscore stats and print log
    write_info(; dir, 
        source      = column_io.source, 
        trajs       = collect(column_io.trajs),
        forms       = [string(nameof(typeof(f))) for f in fit_forms],

        column_io.dims...,

        created     = now(), 
        julia       = string(VERSION),
        sw_vers     = string(pkgversion(SpeedyWeather))
    )
    @info "Zscore statistics $(scheme)_$(unit) stored at $(dir)!"

    return zscore
end










### 2) Coefficient Fits

# Fit per column on centered predictors:
#       - dT   = t1 + t2*(p(T) - ̄p)
#       - olw  = o1 + o2*(p(T[mid]) - ̄p[mid]) + o3*(p(T[bot]) - ̄p[bot])
#       - slwd = s1 + s2*(p(T[mid]) - ̄p[mid]) + s3*(p(T[bot]) - ̄p[bot])
# Algorithm:
#       - 1: For a specific column, do a regression over all n_states_total samples to find coeff_column
#       - 2: Repeat for all columns (nr. of columns = npoints)
#       - 3: Return the raw per-column coefficients — mean/std over columns is taken by coeff_stats
function fit_coeffs(output_form, column_io)

    # Extract dimension of state and layers
    (; npoints, nlayers) = column_io.dims
    mid, bot = mid_layer(nlayers), nlayers


    # Transform the predictors of the output form (LinearOutput: T, PlanckOutput: T^4)
    T  = pred(output_form, column_io.fields.T)

    # Calculate predictor centers (centered after transform, e.g. this is mean(T^4), not mean(T)^4)
    cT  = mean_std_layers(T).mean



    # Temperature tendency coefficients, one fit per column and layer
    t1 = zeros(Float32, npoints, nlayers); t2 = zeros(Float32, npoints, nlayers);

    # Flux coefficients, one fit per column
    o1 = zeros(Float32, npoints); o2 = zeros(Float32, npoints); o3 = zeros(Float32, npoints);
    s1 = zeros(Float32, npoints); s2 = zeros(Float32, npoints); s3 = zeros(Float32, npoints);
    

    # Loop over columns
    for ij in 1:npoints


        ### Temperature

        # Loop over vertical layers
        for k in 1:nlayers

            # Predictor and target of this layer
            x = vec(T[ij, k, :]) .- cT[k]
            y = vec(column_io.fields.dT[ij, k, :])

            # One fit per layer
            t1[ij,k], t2[ij,k] = fit_linear(x, y)
        end


        ### Fluxes

        # Flux predictors
        Pmid = vec(T[ij, mid, :]) .- cT[mid]
        Pbot = vec(T[ij, bot, :]) .- cT[bot]

        # One fit per column
        o1[ij], o2[ij], o3[ij] = fit_linear(Pmid, Pbot, view(column_io.fields.olw, ij, :))
        s1[ij], s2[ij], s3[ij] = fit_linear(Pmid, Pbot, view(column_io.fields.slwd, ij, :))
    end


    # Return coefficents and centers
    return (; coeffs = (; t1, t2, o1, o2, o3, s1, s2, s3), center = (; T = cT))
end










### 3) Statistics Helpers

# Stats of a column_io field,  shape (npoints, nlayers, nstates) or (npoints, nstates)
field_stats(x) = ndims(x) == 3 ? mean_std_layers(x) : mean_std(x)

# Stats of an affine coefficient, shape (npoints, nlayers) or (npoints,)
coeff_stats(x) = ndims(x) == 2 ? mean_std_layers(x) : mean_std(x)


# Mean and std over all entries (for :scalar variables)
function mean_std(x)

    # Filter all nonfinite values
    f = filter(isfinite, x)

    return (; mean = Float32(mean(f)), std = Float32(std(f)))
end

# Mean and std per vertical layer (for :profile variables)
function mean_std_layers(x)

    # Finite entries of each layer, computed once and reused for both statistics
    layers = [filter(isfinite, selectdim(x, 2, k)) for k in axes(x, 2)]

    return (; mean = Float32[mean(f) for f in layers],
              std  = Float32[std(f)  for f in layers])
end